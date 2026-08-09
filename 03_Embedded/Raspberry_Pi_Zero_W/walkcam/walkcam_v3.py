#!/usr/bin/env python3
"""
walkcam_v3.py - 산책 영상 촬영 + 건강 판정

버전: v0.3 (v0.2 기반)

v0.2에서 달라진 것
    1. 외부 제어 API 정리
       run(install_signal_handlers=...) / request_stop() / is_running
       버튼 런처처럼 다른 프로그램이 스레드에서 이 모듈을 구동할 수 있습니다.
       v0.2는 run() 안에서 signal.signal()을 불러 메인 스레드가 아니면
       무조건 실패했고, 종료시키려면 _stop_requested를 직접 건드려야 했습니다.

    2. 공회전 제거
       v0.2의 감시 루프에는 sleep이 없어 CPU를 100% 점유했습니다.
       POLL_INTERVAL이 정의만 되고 쓰이지 않았습니다.
       Pi Zero W는 단일 코어라 이것이 rpicam-vid의 인코딩을 방해해서,
       실제로는 정상인데 STALLED로 오판하게 만드는 원인이 됩니다.
       이제 종료 이벤트를 POLL_INTERVAL만큼 대기하는 방식으로 바꿨습니다.
       CPU를 쓰지 않으면서 종료 요청에는 즉시 반응합니다.

    3. 설정을 CamConfig로 분리
       v0.2는 임계값이 함수 기본 인자에 묶여 있어서, 모듈 상수를 바꿔도
       HealthMonitor에 반영되지 않았습니다. 짧은 임계값으로 테스트하는 것이
       불가능했습니다.

    4. 시작 실패 시에도 자원 정리
       v0.2는 start()가 try 블록 밖에 있어, 세션 디렉터리 생성 후 실패하면
       로그 핸들러가 전역 로거에 그대로 남았습니다. 세션을 반복하면 누적됩니다.

    5. 최종 상태 정정
       v0.2는 유예 시간 안에 종료하면 최종 상태가 STARTING으로 남아
       "최종 상태: 준비 중"이라는 리포트를 출력했습니다.

    6. 이상 원인 추정 추가
       "결과물이 안 자란다"는 사실에서 한 걸음 더 나아가, 디스크 여유 공간과
       프로세스 생존 여부를 확인해 원인 후보를 함께 기록합니다.

    7. 세션 메타데이터 저장 (session.json)
       프레임 추출 이후 단계에서 재사용할 수 있도록 남깁니다.

    8. 시작 전 카메라 존재 확인
       리본 케이블이 빠진 상태(내6)를 20초 기다린 뒤 STALLED로 아는 대신,
       녹화를 시작하기도 전에 알려줍니다.

의도적으로 하지 않은 것
    LED, 버튼 등 하드웨어 제어는 이 모듈에 넣지 않았습니다.
    gpiozero 의존성이 생기면 SSH나 개발 PC에서 이 모듈만 돌려볼 수 없게 됩니다.
    표시 장치는 StatusReporter를 상속해 런처 쪽에서 주입합니다.

사용법
    python3 walkcam_v3.py
    python3 walkcam_v3.py --duration 60
    python3 walkcam_v3.py --dry-run
    python3 walkcam_v3.py --no-probe-camera     # 카메라 사전 확인 생략

    프로그램에서 쓸 때는 walkcam_button.py를 참고하세요.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import shutil
import signal
import subprocess
import sys
import threading
import time
from dataclasses import asdict, dataclass, field, replace
from datetime import datetime
from enum import Enum
from pathlib import Path

# ─────────────────────────────────────────────────────────
# 기본값
# ─────────────────────────────────────────────────────────

SENSOR_MODE = "1296:972"
WIDTH = 1296
HEIGHT = 972
FRAMERATE = 15
BITRATE = 3_000_000
SEGMENT_MS = 300_000
EXPOSURE = "sport"
DENOISE = "cdn_fast"
VERBOSITY = 1

STOP_TIMEOUT = 15.0
POLL_INTERVAL = 0.5

HEALTH_INTERVAL = 5.0
GRACE_PERIOD = 20.0
STALL_THRESHOLD = 20.0
HEARTBEAT_INTERVAL = 60.0

# 시작 전 최소 여유 공간. 3Mbps 기준 1분에 약 22MB가 쌓이므로
# 500MB는 약 22분 분량입니다.
MIN_FREE_MB = 500

# 녹화 중 이 값 아래로 떨어지면 경고합니다.
LOW_DISK_MB = 200

# 카메라 사전 확인 명령의 제한 시간.
PROBE_TIMEOUT = 10.0


def default_output_dir() -> Path:
    env_value = os.environ.get("WALKCAM_OUTPUT")
    if env_value:
        return Path(env_value)

    try:
        return Path.home() / "walk"
    except RuntimeError as e:
        raise RuntimeError(
            "홈 디렉터리를 확인할 수 없습니다. "
            "WALKCAM_OUTPUT 환경 변수로 저장 경로를 직접 지정하세요."
        ) from e


# ─────────────────────────────────────────────────────────
# 설정
# ─────────────────────────────────────────────────────────


@dataclass(frozen=True)
class CamConfig:
    """촬영 및 판정 설정.

    frozen으로 둔 이유: 세션이 시작된 뒤 설정이 바뀌면 리포트와 실제 동작이
    어긋납니다. 값을 바꿀 때는 dataclasses.replace()로 새 설정을 만드세요.

        fast = replace(CamConfig(), grace_period=3.0, stall_threshold=5.0)
    """

    # 촬영
    sensor_mode: str = SENSOR_MODE
    width: int = WIDTH
    height: int = HEIGHT
    framerate: int = FRAMERATE
    bitrate: int = BITRATE
    segment_ms: int = SEGMENT_MS
    exposure: str = EXPOSURE
    denoise: str = DENOISE
    rpicam_verbosity: int = VERBOSITY

    # 저장 위치. None이면 default_output_dir()을 씁니다.
    output_dir: Path | None = None

    # 제어
    stop_timeout: float = STOP_TIMEOUT
    poll_interval: float = POLL_INTERVAL

    # 판정
    health_interval: float = HEALTH_INTERVAL
    grace_period: float = GRACE_PERIOD
    stall_threshold: float = STALL_THRESHOLD
    heartbeat_interval: float = HEARTBEAT_INTERVAL

    # 디스크
    min_free_mb: int = MIN_FREE_MB
    low_disk_mb: int = LOW_DISK_MB

    def resolve_output_dir(self) -> Path:
        return Path(self.output_dir) if self.output_dir else default_output_dir()

    def expected_mb_per_min(self) -> float:
        return self.bitrate / 8 / 1_000_000 * 60


# ─────────────────────────────────────────────────────────
# 상태 정의
# ─────────────────────────────────────────────────────────


class HealthState(Enum):
    STARTING = "준비 중"
    RECORDING = "녹화 중"
    STALLED = "이상 — 데이터 정체"
    STOPPED = "종료됨"


@dataclass
class HealthSample:
    """한 번의 판정 결과."""
    state: HealthState
    changed: bool          # 직전 판정과 상태가 달라졌는가
    total_bytes: int
    mbps: float            # 직전 판정 이후 실효 비트레이트
    stagnant_sec: float    # 마지막으로 자란 뒤 경과 시간
    elapsed_sec: float
    segment_count: int
    free_mb: float


@dataclass
class Event:
    """상태 전이 이력. session.json에 그대로 들어갑니다."""
    wall_time: str
    elapsed_sec: float
    state: str
    detail: str


# ─────────────────────────────────────────────────────────
# 건강 판정 엔진
# ─────────────────────────────────────────────────────────


class HealthMonitor:
    """결과물이 실제로 자라고 있는지 감시합니다.

    프로세스 생존 여부가 아니라 세그먼트 파일의 총 용량 변화를 봅니다.
    카메라가 멈추든, 케이블이 빠지든, 디스크가 읽기 전용이 되든,
    원인과 무관하게 "결과물이 안 나온다"는 사실 하나로 판정합니다.

    v0.3: 설정을 CamConfig로 받습니다. v0.2는 임계값이 함수 기본 인자에
    바인딩되어 있어서 외부에서 조정할 방법이 사실상 없었습니다.
    """

    def __init__(self, session_dir: Path, config: CamConfig):
        self.session_dir = session_dir
        self.config = config

        now = time.monotonic()
        self.started_at = now
        self.last_sample_at = now
        self.last_growth_at = now
        self.last_total = 0
        self.state = HealthState.STARTING

    def _scan(self) -> tuple[int, int]:
        """세그먼트 파일의 개수와 총 용량을 반환합니다."""
        total = 0
        count = 0
        for path in self.session_dir.glob("seg_*.h264"):
            try:
                total += path.stat().st_size
                count += 1
            except (FileNotFoundError, PermissionError):
                # 스캔 도중 파일이 사라지거나 접근 불가한 경우는 건너뜁니다.
                continue
        return total, count

    def _free_mb(self) -> float:
        try:
            return shutil.disk_usage(self.session_dir).free / 1024 / 1024
        except OSError:
            return float("nan")

    def scan_totals(self) -> tuple[int, int]:
        """외부에서 쓰는 공개 스캔. v0.2에서 _scan()을 외부에서 부르던 것을 정리."""
        return self._scan()

    def sample(self) -> HealthSample:
        now = time.monotonic()
        total, count = self._scan()

        interval = max(now - self.last_sample_at, 1e-6)
        delta = total - self.last_total
        mbps = (delta * 8) / interval / 1_000_000 if delta > 0 else 0.0

        if total != self.last_total:
            self.last_total = total
            self.last_growth_at = now
        self.last_sample_at = now

        elapsed = now - self.started_at
        stagnant = now - self.last_growth_at

        # 판정 순서가 중요합니다.
        # total == 0을 먼저 처리하지 않으면, 유예 시간 직후
        # (stagnant < stall인 구간에서) 빈 폴더를 정상으로 오판합니다.
        if total == 0:
            state = (
                HealthState.STARTING if elapsed < self.config.grace_period
                else HealthState.STALLED
            )
        elif stagnant >= self.config.stall_threshold:
            state = HealthState.STALLED
        else:
            state = HealthState.RECORDING

        changed = state is not self.state
        self.state = state

        return HealthSample(
            state=state,
            changed=changed,
            total_bytes=total,
            mbps=mbps,
            stagnant_sec=stagnant,
            elapsed_sec=elapsed,
            segment_count=count,
            free_mb=self._free_mb(),
        )


# ─────────────────────────────────────────────────────────
# 상태 리포터 — 표시 방식을 갈아끼우는 지점
# ─────────────────────────────────────────────────────────


class StatusReporter:
    """상태를 외부에 알리는 방법의 인터페이스.

    LED, 부저, 네트워크 알림 등은 이 클래스를 상속해서 런처 쪽에서 주입합니다.
    판정 로직은 건드리지 않습니다.
    """

    def on_start(self, session_dir: Path) -> None:
        pass

    def on_state_change(self, sample: HealthSample) -> None:
        pass

    def on_heartbeat(self, sample: HealthSample) -> None:
        pass

    def on_finish(self, final_state: HealthState) -> None:
        pass

    def close(self) -> None:
        pass


class LogReporter(StatusReporter):
    """로그로만 상태를 알립니다.

    한계: SSH 접속이 가능할 때만 확인할 수 있으므로
    야외 촬영 중에는 내7(관측 불가)을 해결하지 못합니다.
    LedReporter와 함께 CompositeReporter로 묶어 쓰세요.
    """

    def __init__(self, log: logging.Logger):
        self.log = log

    def on_state_change(self, sample: HealthSample) -> None:
        if sample.state is HealthState.STALLED:
            self.log.warning(
                "상태 변경 → %s | %.0f초간 데이터 증가 없음 | 총 %.1f MB",
                sample.state.value,
                sample.stagnant_sec,
                sample.total_bytes / 1024 / 1024,
            )
        elif sample.state is HealthState.RECORDING:
            self.log.info(
                "상태 변경 → %s | %.2f Mbps | 세그먼트 %d개",
                sample.state.value, sample.mbps, sample.segment_count,
            )
        else:
            self.log.info("상태 변경 → %s", sample.state.value)

    def on_heartbeat(self, sample: HealthSample) -> None:
        self.log.info(
            "경과 %.0f분 | %s | %.2f Mbps | 세그먼트 %d개 | 총 %.1f MB | 여유 %.0f MB",
            sample.elapsed_sec / 60,
            sample.state.value,
            sample.mbps,
            sample.segment_count,
            sample.total_bytes / 1024 / 1024,
            sample.free_mb,
        )

    def on_finish(self, final_state: HealthState) -> None:
        self.log.info("최종 상태: %s", final_state.value)


class CompositeReporter(StatusReporter):
    """여러 리포터를 동시에 사용합니다. 로그 + LED 조합에 사용."""

    def __init__(self, *reporters: StatusReporter):
        self.reporters = list(reporters)

    def _fanout(self, method: str, *args) -> None:
        # 한 리포터가 실패해도 나머지는 계속 동작해야 합니다.
        # LED 하나가 고장 났다고 로그까지 끊기면 진단이 불가능해집니다.
        for r in self.reporters:
            try:
                getattr(r, method)(*args)
            except Exception:
                logging.getLogger("walkcam").exception(
                    "리포터 %s.%s 실패", type(r).__name__, method
                )

    def on_start(self, session_dir: Path) -> None:
        self._fanout("on_start", session_dir)

    def on_state_change(self, sample: HealthSample) -> None:
        self._fanout("on_state_change", sample)

    def on_heartbeat(self, sample: HealthSample) -> None:
        self._fanout("on_heartbeat", sample)

    def on_finish(self, final_state: HealthState) -> None:
        self._fanout("on_finish", final_state)

    def close(self) -> None:
        self._fanout("close")


# ─────────────────────────────────────────────────────────
# 결과
# ─────────────────────────────────────────────────────────


@dataclass
class SessionResult:
    session_dir: Path | None
    duration_sec: float
    segment_count: int
    total_bytes: int
    final_state: HealthState
    stall_count: int
    config: CamConfig
    events: list[Event] = field(default_factory=list)
    process_returncode: int | None = None

    @property
    def average_mbps(self) -> float:
        if self.duration_sec <= 0:
            return 0.0
        return self.total_bytes * 8 / self.duration_sec / 1_000_000

    def to_dict(self) -> dict:
        cfg = asdict(self.config)
        cfg["output_dir"] = str(self.config.resolve_output_dir())
        return {
            "session_dir": str(self.session_dir) if self.session_dir else None,
            "recorded_at": datetime.now().isoformat(timespec="seconds"),
            "duration_sec": self.duration_sec,
            "segment_count": self.segment_count,
            "total_bytes": self.total_bytes,
            "average_mbps": round(self.average_mbps, 3),
            "final_state": self.final_state.name,
            "stall_count": self.stall_count,
            "process_returncode": self.process_returncode,
            "config": cfg,
            "events": [asdict(e) for e in self.events],
        }


# ─────────────────────────────────────────────────────────
# 녹화 관리
# ─────────────────────────────────────────────────────────


class WalkCam:
    """한 번의 녹화 세션.

    인스턴스는 1회용입니다. run()을 두 번 부르면 RuntimeError가 납니다.
    session_dir, events, stall_count가 모두 세션 단위 상태이기 때문입니다.
    (v0.2는 재사용 시 두 번째 run()이 조용히 즉시 종료됐습니다.)

    스레드에서 쓸 때
        cam = WalkCam(reporter=my_reporter)
        t = threading.Thread(target=cam.run)     # 시그널 설치 안 함이 기본값
        t.start()
        ...
        cam.request_stop()                       # 어느 스레드에서든 호출 가능
        t.join()
    """

    def __init__(
        self,
        duration: float | None = None,
        config: CamConfig | None = None,
        reporter: StatusReporter | None = None,
        logger: logging.Logger | None = None,
    ):
        self.duration = duration
        self.config = config or CamConfig()
        self.log = logger or logging.getLogger("walkcam")
        self.reporter: StatusReporter = reporter or LogReporter(self.log)

        self.proc: subprocess.Popen | None = None
        self.session_dir: Path | None = None
        self.rpicam_log_handle = None
        self.file_log_handler: logging.Handler | None = None

        self.monitor: HealthMonitor | None = None

        self.started_at: float | None = None
        self.events: list[Event] = []
        self.stall_count = 0

        # bool 대신 Event를 쓰는 이유
        #   1. 다른 스레드에서 세우는 깃발이므로 의미가 명확합니다.
        #   2. wait(timeout)이 곧 루프의 sleep 역할을 합니다.
        #      공회전 없이, 종료 요청에는 즉시 반응합니다.
        self._stop_event = threading.Event()
        self._used = False
        self._prev_handlers: dict = {}

    # ── 공개 제어 API ────────────────────────────────────

    def request_stop(self) -> None:
        """녹화 종료를 요청합니다. 어느 스레드에서든 호출할 수 있습니다.

        즉시 반환합니다. 실제 종료는 run()이 처리하며 최대 stop_timeout이
        걸릴 수 있습니다. 완료를 기다려야 하면 스레드를 join하세요.
        """
        self._stop_event.set()

    @property
    def stop_requested(self) -> bool:
        return self._stop_event.is_set()

    @property
    def is_running(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

    # ── 준비 ─────────────────────────────────────────────

    @staticmethod
    def check_environment(
        config: CamConfig | None = None,
        probe_camera: bool = True,
    ) -> None:
        """녹화를 시작할 수 있는 상태인지 확인합니다.

        실패 원인을 녹화 시작 20초 뒤 STALLED가 아니라 지금 알려주는 것이
        목적입니다.
        """
        cfg = config or CamConfig()
        log = logging.getLogger("walkcam")

        if shutil.which("rpicam-vid") is None:
            raise RuntimeError(
                "rpicam-vid를 찾을 수 없습니다. rpicam-apps 설치를 확인하세요."
            )

        out_dir = cfg.resolve_output_dir()
        try:
            out_dir.mkdir(parents=True, exist_ok=True)
        except OSError as e:
            raise RuntimeError(f"저장 경로를 만들 수 없습니다: {out_dir} ({e})") from e

        if not os.access(out_dir, os.W_OK):
            raise RuntimeError(f"저장 경로에 쓸 수 없습니다: {out_dir}")

        free_mb = shutil.disk_usage(out_dir).free / 1024 / 1024
        if free_mb < cfg.min_free_mb:
            raise RuntimeError(
                f"디스크 여유 공간이 부족합니다: {free_mb:.0f} MB "
                f"(최소 {cfg.min_free_mb} MB 필요, "
                f"약 {cfg.expected_mb_per_min():.0f} MB/분 소비)"
            )
        log.info(
            "디스크 여유 %.0f MB (약 %.0f분 녹화 가능)",
            free_mb, free_mb / cfg.expected_mb_per_min(),
        )

        if probe_camera:
            WalkCam._probe_camera(log)

    @staticmethod
    def _probe_camera(log: logging.Logger) -> None:
        """카메라가 실제로 보이는지 확인합니다.

        리본 케이블이 빠졌거나 반대로 꽂힌 경우(내6)를 여기서 잡습니다.
        출력 형식이 rpicam-apps 버전에 따라 다를 수 있으므로,
        "없다"고 확실히 말하는 경우에만 오류로 처리하고
        판단이 애매하면 경고만 남기고 진행합니다.
        """
        try:
            proc = subprocess.run(
                ["rpicam-vid", "--list-cameras"],
                capture_output=True, text=True, timeout=PROBE_TIMEOUT,
            )
        except subprocess.TimeoutExpired:
            log.warning("카메라 확인이 %.0f초 내에 끝나지 않았습니다. 그대로 진행합니다.",
                        PROBE_TIMEOUT)
            return
        except OSError as e:
            log.warning("카메라 확인을 실행할 수 없습니다: %s", e)
            return

        output = (proc.stdout or "") + (proc.stderr or "")

        if "no cameras available" in output.lower():
            raise RuntimeError(
                "카메라가 감지되지 않습니다.\n"
                "  확인: 리본 케이블 체결 방향과 삽입 깊이 / 커넥터 래치 / "
                "raspi-config의 카메라 활성화"
            )

        for line in output.splitlines():
            stripped = line.strip()
            # "0 : ov5647 [2592x1944 10-bit RGGB] (/base/soc/...)" 형태
            if stripped[:1].isdigit() and ":" in stripped:
                log.info("카메라 감지: %s", stripped)
                return

        log.warning("카메라 목록을 해석할 수 없습니다. 그대로 진행합니다.")

    def _create_session_dir(self) -> Path:
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_dir = self.config.resolve_output_dir()
        base_name = f"session_{stamp}"
        session_dir = output_dir / base_name
        suffix = 1
        while True:
            try:
                session_dir.mkdir(parents=True, exist_ok=False)
                return session_dir
            except FileExistsError:
                session_dir = output_dir / f"{base_name}_{suffix:03d}"
                suffix += 1

    def _attach_file_log(self, session_dir: Path) -> None:
        """세션 폴더에 walkcam 자체 로그를 남깁니다.

        rpicam.log(일꾼의 출력)와는 별개입니다.
        """
        handler = logging.FileHandler(session_dir / "walkcam.log", encoding="utf-8")
        handler.setFormatter(
            logging.Formatter(
                "%(asctime)s [%(levelname)s] %(message)s",
                datefmt="%Y-%m-%d %H:%M:%S",
            )
        )
        self.log.addHandler(handler)
        self.file_log_handler = handler

    def _detach_file_log(self) -> None:
        if self.file_log_handler is not None:
            self.log.removeHandler(self.file_log_handler)
            self.file_log_handler.close()
            self.file_log_handler = None

    def build_command(self, session_dir: Path) -> list[str]:
        # 주의: --segment 사용 시 출력 경로에 %04d가 반드시 있어야 합니다.
        # 없으면 오류 없이 같은 파일을 계속 덮어씁니다.
        cfg = self.config
        output_pattern = str(session_dir / "seg_%04d.h264")
        return [
            "rpicam-vid",
            "--nopreview",
            "--timeout", "0",
            "--mode", cfg.sensor_mode,
            "--width", str(cfg.width),
            "--height", str(cfg.height),
            "--framerate", str(cfg.framerate),
            "--codec", "h264",
            "--bitrate", str(cfg.bitrate),
            "--intra", str(cfg.framerate),
            "--inline",
            "--flush",
            "--exposure", cfg.exposure,
            "--denoise", cfg.denoise,
            "--segment", str(cfg.segment_ms),
            "--verbose", str(cfg.rpicam_verbosity),
            "--output", output_pattern,
        ]

    # ── 신호 처리 ────────────────────────────────────────

    def _install_handlers(self) -> None:
        """SIGINT/SIGTERM을 종료 요청으로 연결합니다.

        메인 스레드에서만 호출할 수 있습니다. 그래서 run()의 기본값은
        설치하지 않는 쪽입니다. CLI(main)만 True로 넘깁니다.
        """
        for sig in (signal.SIGINT, signal.SIGTERM):
            self._prev_handlers[sig] = signal.getsignal(sig)
            signal.signal(sig, self._on_signal)

    def _restore_handlers(self) -> None:
        """원래 핸들러를 되돌립니다.

        v0.2는 되돌리지 않아서, 한 프로세스에서 두 번째 세션을 돌리면
        SIGINT가 이미 끝난 세션의 깃발을 세우고 아무 일도 일어나지 않았습니다.
        """
        for sig, prev in self._prev_handlers.items():
            try:
                signal.signal(sig, prev)
            except (ValueError, OSError, TypeError):
                pass
        self._prev_handlers.clear()

    def _on_signal(self, signum, frame) -> None:
        # 핸들러에서는 깃발만 세웁니다. 정리는 메인 루프가 담당합니다.
        self._stop_event.set()

    # ── 이력 기록 ────────────────────────────────────────

    def _record_event(self, state: HealthState, detail: str) -> None:
        elapsed = time.monotonic() - self.started_at if self.started_at else 0.0
        self.events.append(
            Event(
                wall_time=datetime.now().isoformat(timespec="seconds"),
                elapsed_sec=round(elapsed, 1),
                state=state.name,
                detail=detail,
            )
        )

    def _diagnose_stall(self, sample: HealthSample) -> str:
        """정체의 원인 후보를 좁힙니다.

        "결과물이 안 자란다"는 판정은 원인과 무관하게 옳지만,
        현장에서 손을 쓰려면 어디를 봐야 하는지가 필요합니다.
        """
        hints: list[str] = []

        if sample.free_mb == sample.free_mb and sample.free_mb < self.config.low_disk_mb:
            hints.append(f"디스크 여유 {sample.free_mb:.0f} MB — 공간 부족 유력")

        if self.proc is not None and self.proc.poll() is not None:
            hints.append(f"rpicam-vid 종료됨 (rc={self.proc.returncode})")
        else:
            hints.append("rpicam-vid는 살아있음 — 카메라 무응답 또는 케이블 접촉 의심")

        if sample.segment_count == 0:
            hints.append("세그먼트 파일이 하나도 생성되지 않음")

        return " / ".join(hints)

    # ── 실행 ─────────────────────────────────────────────

    def start(self) -> None:
        self.session_dir = self._create_session_dir()
        self._attach_file_log(self.session_dir)

        cfg = self.config
        rpicam_log_path = self.session_dir / "rpicam.log"
        cmd = self.build_command(self.session_dir)

        self.log.info("세션 디렉터리: %s", self.session_dir)
        self.log.info(
            "촬영 설정: %dx%d @ %dfps, %.1fMbps, %d초 분할",
            cfg.width, cfg.height, cfg.framerate,
            cfg.bitrate / 1_000_000, cfg.segment_ms // 1000,
        )
        self.log.info(
            "판정 설정: %.0f초 주기, 유예 %.0f초, 정체 기준 %.0f초",
            cfg.health_interval, cfg.grace_period, cfg.stall_threshold,
        )

        # stderr는 반드시 파일로 보냅니다.
        # subprocess.PIPE를 쓰고 읽지 않으면 파이프 버퍼(약 64KB)가 차서
        # rpicam-vid가 블로킹됩니다. 장시간 녹화에서 확실히 발생합니다.
        self.rpicam_log_handle = rpicam_log_path.open("wb")

        try:
            self.started_at = time.monotonic()
            self.proc = subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=self.rpicam_log_handle,
                start_new_session=True,
            )
        except Exception:
            self.rpicam_log_handle.close()
            self.rpicam_log_handle = None
            raise

        self.monitor = HealthMonitor(self.session_dir, self.config)
        self._record_event(HealthState.STARTING, f"rpicam-vid 시작 (PID {self.proc.pid})")
        self.log.info("녹화 시작 (PID %d)", self.proc.pid)
        self.reporter.on_start(self.session_dir)

    def stop(self) -> None:
        if self.proc is None or self.proc.poll() is not None:
            return

        self.log.info("종료 신호 전송...")
        try:
            self.proc.send_signal(signal.SIGINT)
        except ProcessLookupError:
            return

        try:
            self.proc.wait(timeout=self.config.stop_timeout)
            self.log.info("정상 종료됨")
        except subprocess.TimeoutExpired:
            self.log.warning("%.0f초 내 응답 없음 → 강제 종료", self.config.stop_timeout)
            self.proc.kill()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.log.error("프로세스가 종료되지 않았습니다")

    def _monitor_loop(self) -> int:
        """녹화 중 감시 루프. 반환값은 종료 코드입니다."""
        cfg = self.config
        exit_code = 0
        last_health = time.monotonic()
        last_heartbeat = time.monotonic()

        while not self._stop_event.is_set():
            # 이 wait이 sleep 역할을 합니다.
            # 종료 요청이 오면 timeout을 기다리지 않고 즉시 깨어납니다.
            # v0.2는 sleep이 없어 CPU를 100% 점유했습니다.
            self._stop_event.wait(timeout=cfg.poll_interval)
            if self._stop_event.is_set():
                break

            now = time.monotonic()

            returncode = self.proc.poll()
            if returncode is not None:
                self.log.warning(
                    "rpicam-vid가 스스로 종료되었습니다 (rc=%d)", returncode
                )
                self._record_event(
                    HealthState.STOPPED, f"프로세스 종료 rc={returncode}"
                )
                if returncode != 0:
                    exit_code = 1
                break

            if self.duration is not None and (now - self.started_at) >= self.duration:
                self.log.info("지정 시간(%.0f초) 도달", self.duration)
                break

            if now - last_health >= cfg.health_interval:
                last_health = now
                sample = self.monitor.sample()

                if sample.changed:
                    self.reporter.on_state_change(sample)
                    if sample.state is HealthState.STALLED:
                        self.stall_count += 1
                        detail = (
                            f"{sample.stagnant_sec:.0f}초간 데이터 증가 없음 | "
                            f"{self._diagnose_stall(sample)}"
                        )
                        self.log.warning("  점검: %s", self._diagnose_stall(sample))
                        self._record_event(sample.state, detail)
                    else:
                        self._record_event(sample.state, "")

                if now - last_heartbeat >= cfg.heartbeat_interval:
                    last_heartbeat = now
                    self.reporter.on_heartbeat(sample)

        if self._stop_event.is_set():
            self.log.info("종료 요청 수신")

        return exit_code

    def run(self, install_signal_handlers: bool = False) -> int:
        """세션을 실행합니다. 종료될 때까지 블로킹됩니다.

        install_signal_handlers
            True면 SIGINT/SIGTERM을 종료 요청으로 연결합니다.
            메인 스레드에서만 True를 쓸 수 있습니다. 워커 스레드에서는
            signal.signal()이 ValueError를 던집니다.
            기본값이 False라서, 스레드에서 그냥 run을 넘겨도 동작합니다.
        """
        if self._used:
            raise RuntimeError(
                "WalkCam 인스턴스는 1회용입니다. "
                "새 세션에는 새 인스턴스를 만드세요."
            )
        self._used = True

        if install_signal_handlers:
            self._install_handlers()

        exit_code = 0
        started = False

        try:
            try:
                self.start()
                started = True
            except Exception:
                # v0.2는 start()가 try 밖에 있어, 여기서 실패하면
                # 로그 핸들러가 전역 로거에 남고 리포터도 닫히지 않았습니다.
                self.log.exception("녹화를 시작할 수 없습니다")
                return 1

            exit_code = self._monitor_loop()

        finally:
            if started:
                self.stop()

            if self.rpicam_log_handle is not None:
                self.rpicam_log_handle.close()
                self.rpicam_log_handle = None

            result = self._build_result()

            # 마지막 상태가 이상이면 실패로 처리합니다.
            # 중간에 발생했다가 회복된 경우는 성공으로 두되 이력에 남깁니다.
            if result.final_state is HealthState.STALLED:
                exit_code = 1

            self._record_event(result.final_state, "세션 종료")

            try:
                self.reporter.on_finish(result.final_state)
            finally:
                self.reporter.close()

            if started:
                self._write_metadata(result)
                self._print_report(result)

            self._detach_file_log()
            self._restore_handlers()
            self.last_result = result

        return exit_code

    # ── 결과 정리 ────────────────────────────────────────

    def _build_result(self) -> SessionResult:
        total, count = self.monitor.scan_totals() if self.monitor else (0, 0)
        elapsed = time.monotonic() - self.started_at if self.started_at else 0.0

        # v0.2는 monitor.state를 그대로 썼기 때문에, 유예 시간 안에 멈추면
        # 최종 상태가 STARTING("준비 중")으로 남는 이상한 리포트가 나왔습니다.
        if self.monitor is None:
            final_state = HealthState.STOPPED
        elif self.monitor.state is HealthState.STALLED:
            final_state = HealthState.STALLED
        else:
            final_state = HealthState.STOPPED

        return SessionResult(
            session_dir=self.session_dir,
            duration_sec=round(elapsed, 1),
            segment_count=count,
            total_bytes=total,
            final_state=final_state,
            stall_count=self.stall_count,
            config=self.config,
            events=self.events,
            process_returncode=self.proc.returncode if self.proc else None,
        )

    def _write_metadata(self, result: SessionResult) -> None:
        """다음 단계(프레임 추출 → 관측 생성)에서 쓸 메타데이터를 남깁니다."""
        if self.session_dir is None:
            return
        path = self.session_dir / "session.json"
        try:
            path.write_text(
                json.dumps(result.to_dict(), ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            self.log.info("메타데이터 저장: %s", path.name)
        except OSError as e:
            # 메타데이터 실패가 영상까지 실패로 만들지 않도록 경고만 남깁니다.
            self.log.warning("메타데이터를 저장하지 못했습니다: %s", e)

    def _print_report(self, result: SessionResult) -> None:
        log = self.log
        log.info("─" * 52)
        log.info("녹화 시간   : %.1f초 (%.1f분)",
                 result.duration_sec, result.duration_sec / 60)
        log.info("세그먼트    : %d개", result.segment_count)
        log.info("총 용량     : %.1f MB", result.total_bytes / 1024 / 1024)
        if result.duration_sec > 0:
            log.info("평균 비트레이트: %.2f Mbps", result.average_mbps)
        log.info("이상 감지   : %d회", result.stall_count)
        log.info("저장 위치   : %s", result.session_dir)
        log.info("─" * 52)

        if result.stall_count > 0:
            log.warning("촬영 중 %d회 이상이 감지되었습니다. 이력:", result.stall_count)
            for ev in result.events:
                if ev.state == HealthState.STALLED.name:
                    log.warning("  [%s] +%.0f초 — %s",
                                ev.wall_time, ev.elapsed_sec, ev.detail)

        if result.segment_count == 0:
            log.error("생성된 세그먼트가 없습니다.")
            if result.session_dir:
                log.error("확인: %s", result.session_dir / "rpicam.log")


# ─────────────────────────────────────────────────────────


def setup_console_logging(verbose: bool = False) -> logging.Logger:
    log = logging.getLogger("walkcam")
    log.setLevel(logging.DEBUG if verbose else logging.INFO)
    log.propagate = False

    # 중복 호출 시 핸들러가 쌓이지 않게 합니다.
    if not any(isinstance(h, logging.StreamHandler) for h in log.handlers):
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(
            logging.Formatter("%(asctime)s [%(levelname)s] %(message)s",
                              datefmt="%H:%M:%S")
        )
        log.addHandler(handler)

    return log


def main() -> int:
    parser = argparse.ArgumentParser(
        description="산책 영상 촬영 + 건강 판정 (v0.3)"
    )
    parser.add_argument("--duration", type=float, default=None,
                        help="녹화 시간(초). 생략하면 무한")
    parser.add_argument("--output-dir", type=Path, default=None,
                        help="저장 경로. 생략하면 WALKCAM_OUTPUT 또는 ~/walk")
    parser.add_argument("--dry-run", action="store_true",
                        help="실행하지 않고 명령만 출력")
    parser.add_argument("--no-probe-camera", action="store_true",
                        help="시작 전 카메라 감지 확인을 생략")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    log = setup_console_logging(args.verbose)
    config = CamConfig(output_dir=args.output_dir)

    if args.dry_run:
        fake_dir = config.resolve_output_dir() / "session_YYYYmmdd_HHMMSS"
        print(" ".join(WalkCam(config=config).build_command(fake_dir)))
        return 0

    try:
        WalkCam.check_environment(config, probe_camera=not args.no_probe_camera)
    except RuntimeError as e:
        log.error("%s", e)
        return 1

    cam = WalkCam(duration=args.duration, config=config)

    try:
        # CLI는 메인 스레드이므로 시그널 핸들러를 설치합니다.
        return cam.run(install_signal_handlers=True)
    except Exception as e:
        log.exception("실행 중 오류: %s", e)
        return 1


if __name__ == "__main__":
    sys.exit(main())
