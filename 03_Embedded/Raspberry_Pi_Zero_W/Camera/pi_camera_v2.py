#!/usr/bin/env python3
"""
walkcam_v02.py - 산책 영상 촬영 + 건강 판정

버전: v0.2 (v0.1 기반)
추가된 것
    - 건강 판정 엔진: 결과물이 실제로 자라고 있는지 감시
    - 상태 리포터 구조: 표시 방식을 갈아끼울 수 있음
    - 세션 로그 파일 및 이상 이력 기록

해결하는 페인 포인트
    내8  무응답 실패      → 파일 미성장으로 탐지
    내6  케이블 접촉 불량  → 동일 증상으로 탐지

아직 해결하지 못한 것
    내7  관측 불가 → 로그는 SSH로만 볼 수 있어 현장에서 무용.
                     v0.2b에서 LedReporter 등을 추가해 해결 예정.

핵심 아이디어
    v0.1은 "프로세스가 살아있는가"만 확인했다.
    그러나 내8은 정확히 "프로세스는 살아있는데 아무것도 안 하는" 상태다.
    따라서 판정 기준을 프로세스가 아니라 **결과물**로 옮긴다.

사용법
    python3 pi_camera_v2.py
    python3 pi_camera_v2.py --duration 60
    python3 pi_camera_v2.py --dry-run
"""

from __future__ import annotations

import argparse
import logging
import os
import shutil
import signal
import subprocess
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from pathlib import Path

# ─────────────────────────────────────────────────────────
# 촬영 설정 (v0.1과 동일)
# ─────────────────────────────────────────────────────────

OUTPUT_DIR = Path(os.environ.get("WALKCAM_OUTPUT", Path.home() / "walk"))

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

# ─────────────────────────────────────────────────────────
# 건강 판정 설정 (v0.2 신규)
# ─────────────────────────────────────────────────────────

# 판정 주기. 이 간격으로 파일 크기를 확인합니다.
HEALTH_INTERVAL = 5.0

# 시작 유예. 카메라 초기화에 수 초가 걸리므로,
# 이 시간 동안 파일이 비어 있어도 이상으로 보지 않습니다.
GRACE_PERIOD = 20.0

# 정체 판정 기준. 이 시간 동안 총 용량이 변하지 않으면 이상입니다.
# 3Mbps 기준 초당 375KB가 쌓이므로, 20초면 7.5MB 차이가 납니다.
# 정상과 이상이 명확히 갈리는 값입니다.
STALL_THRESHOLD = 20.0

# 정상 동작 중 상태를 로그에 남기는 주기.
HEARTBEAT_INTERVAL = 60.0


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


@dataclass
class Event:
    """상태 전이 이력. v0.5 메타데이터에서 재사용합니다."""
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
    """

    def __init__(
        self,
        session_dir: Path,
        grace: float = GRACE_PERIOD,
        stall: float = STALL_THRESHOLD,
    ):
        self.session_dir = session_dir
        self.grace = grace
        self.stall = stall

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
                HealthState.STARTING if elapsed < self.grace
                else HealthState.STALLED
            )
        elif stagnant >= self.stall:
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
        )


# ─────────────────────────────────────────────────────────
# 상태 리포터 — 표시 방식을 갈아끼우는 지점
# ─────────────────────────────────────────────────────────


class StatusReporter:
    """상태를 외부에 알리는 방법의 인터페이스.

    v0.2b에서 LedReporter, BuzzerReporter 등을 이 클래스를 상속해
    추가할 예정입니다. 판정 로직은 건드리지 않습니다.
    """

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
            self.log.warning(
                "  점검: 리본 케이블 체결 / 카메라 전원 / 디스크 상태"
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
            "경과 %.0f분 | %s | %.2f Mbps | 세그먼트 %d개 | 총 %.1f MB",
            sample.elapsed_sec / 60,
            sample.state.value,
            sample.mbps,
            sample.segment_count,
            sample.total_bytes / 1024 / 1024,
        )

    def on_finish(self, final_state: HealthState) -> None:
        self.log.info("최종 상태: %s", final_state.value)


class CompositeReporter(StatusReporter):
    """여러 리포터를 동시에 사용합니다. v0.2b에서 로그 + LED 조합에 사용."""

    def __init__(self, *reporters: StatusReporter):
        self.reporters = list(reporters)

    def on_state_change(self, sample: HealthSample) -> None:
        for r in self.reporters:
            r.on_state_change(sample)

    def on_heartbeat(self, sample: HealthSample) -> None:
        for r in self.reporters:
            r.on_heartbeat(sample)

    def on_finish(self, final_state: HealthState) -> None:
        for r in self.reporters:
            r.on_finish(final_state)

    def close(self) -> None:
        for r in self.reporters:
            r.close()


# ─────────────────────────────────────────────────────────
# 녹화 관리
# ─────────────────────────────────────────────────────────


@dataclass
class SessionResult:
    session_dir: Path
    duration_sec: float
    segment_count: int
    total_bytes: int
    final_state: HealthState
    stall_count: int
    events: list[Event] = field(default_factory=list)
    process_returncode: int | None = None


class WalkCam:
    def __init__(self, duration: float | None = None):
        self.duration = duration
        self.log = logging.getLogger("walkcam")

        self.proc: subprocess.Popen | None = None
        self.session_dir: Path | None = None
        self.rpicam_log_handle = None
        self.file_log_handler: logging.Handler | None = None

        self.monitor: HealthMonitor | None = None
        self.reporter: StatusReporter = LogReporter(self.log)

        self.started_at: float | None = None
        self.events: list[Event] = []
        self.stall_count = 0
        self._stop_requested = False

    # ── 준비 ─────────────────────────────────────────────

    @staticmethod
    def check_environment() -> None:
        if shutil.which("rpicam-vid") is None:
            raise RuntimeError(
                "rpicam-vid를 찾을 수 없습니다. rpicam-apps 설치를 확인하세요."
            )

    def _create_session_dir(self) -> Path:
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        session_dir = OUTPUT_DIR / f"session_{stamp}"
        session_dir.mkdir(parents=True, exist_ok=True)
        return session_dir

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
        logging.getLogger("walkcam").addHandler(handler)
        self.file_log_handler = handler

    def build_command(self, session_dir: Path) -> list[str]:
        # 주의: --segment 사용 시 출력 경로에 %04d가 반드시 있어야 합니다.
        # 없으면 오류 없이 같은 파일을 계속 덮어씁니다.
        output_pattern = str(session_dir / "seg_%04d.h264")
        return [
            "rpicam-vid",
            "--nopreview",
            "--timeout", "0",
            "--mode", SENSOR_MODE,
            "--width", str(WIDTH),
            "--height", str(HEIGHT),
            "--framerate", str(FRAMERATE),
            "--codec", "h264",
            "--bitrate", str(BITRATE),
            "--intra", str(FRAMERATE),
            "--inline",
            "--flush",
            "--exposure", EXPOSURE,
            "--denoise", DENOISE,
            "--segment", str(SEGMENT_MS),
            "--verbose", str(VERBOSITY),
            "--output", output_pattern,
        ]

    # ── 신호 처리 ────────────────────────────────────────

    def _install_handlers(self) -> None:
        signal.signal(signal.SIGINT, self._on_signal)
        signal.signal(signal.SIGTERM, self._on_signal)

    def _on_signal(self, signum, frame) -> None:
        # 핸들러에서는 깃발만 세웁니다. 정리는 메인 루프가 담당합니다.
        self._stop_requested = True

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

    # ── 실행 ─────────────────────────────────────────────

    def start(self) -> None:
        self.session_dir = self._create_session_dir()
        self._attach_file_log(self.session_dir)

        rpicam_log_path = self.session_dir / "rpicam.log"
        cmd = self.build_command(self.session_dir)

        self.log.info("세션 디렉터리: %s", self.session_dir)
        self.log.info(
            "촬영 설정: %dx%d @ %dfps, %.1fMbps, %d초 분할",
            WIDTH, HEIGHT, FRAMERATE, BITRATE / 1_000_000, SEGMENT_MS // 1000,
        )
        self.log.info(
            "판정 설정: %.0f초 주기, 유예 %.0f초, 정체 기준 %.0f초",
            HEALTH_INTERVAL, GRACE_PERIOD, STALL_THRESHOLD,
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

        self.monitor = HealthMonitor(self.session_dir)
        self._record_event(HealthState.STARTING, f"rpicam-vid 시작 (PID {self.proc.pid})")
        self.log.info("녹화 시작 (PID %d)", self.proc.pid)

    def stop(self) -> None:
        if self.proc is None or self.proc.poll() is not None:
            return

        self.log.info("종료 신호 전송...")
        try:
            self.proc.send_signal(signal.SIGINT)
        except ProcessLookupError:
            return

        try:
            self.proc.wait(timeout=STOP_TIMEOUT)
            self.log.info("정상 종료됨")
        except subprocess.TimeoutExpired:
            self.log.warning("%.0f초 내 응답 없음 → 강제 종료", STOP_TIMEOUT)
            self.proc.kill()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.log.error("프로세스가 종료되지 않았습니다")

    def _build_result(self) -> SessionResult:
        total, count = (self.monitor._scan() if self.monitor else (0, 0))
        elapsed = time.monotonic() - self.started_at if self.started_at else 0.0
        return SessionResult(
            session_dir=self.session_dir,
            duration_sec=round(elapsed, 1),
            segment_count=count,
            total_bytes=total,
            final_state=self.monitor.state if self.monitor else HealthState.STOPPED,
            stall_count=self.stall_count,
            events=self.events,
            process_returncode=self.proc.returncode if self.proc else None,
        )

    def _print_report(self, result: SessionResult) -> None:
        log = self.log
        log.info("─" * 52)
        log.info("녹화 시간   : %.1f초 (%.1f분)",
                 result.duration_sec, result.duration_sec / 60)
        log.info("세그먼트    : %d개", result.segment_count)
        log.info("총 용량     : %.1f MB", result.total_bytes / 1024 / 1024)
        if result.duration_sec > 0:
            log.info("평균 비트레이트: %.2f Mbps",
                     result.total_bytes * 8 / result.duration_sec / 1_000_000)
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
            log.error("확인: %s", result.session_dir / "rpicam.log")

    def run(self) -> int:
        self._install_handlers()
        self.start()

        exit_code = 0
        last_health = time.monotonic()
        last_heartbeat = time.monotonic()

        try:
            while not self._stop_requested:
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

                if self.duration is not None:
                    if (now - self.started_at) >= self.duration:
                        self.log.info("지정 시간(%.0f초) 도달", self.duration)
                        break

                # ── 건강 판정 ──
                if now - last_health >= HEALTH_INTERVAL:
                    last_health = now
                    sample = self.monitor.sample()

                    if sample.changed:
                        self.reporter.on_state_change(sample)
                        if sample.state is HealthState.STALLED:
                            self.stall_count += 1
                            self._record_event(
                                sample.state,
                                f"{sample.stagnant_sec:.0f}초간 데이터 증가 없음",
                            )
                        else:
                            self._record_event(sample.state, "")

                    if now - last_heartbeat >= HEARTBEAT_INTERVAL:
                        last_heartbeat = now
                        self.reporter.on_heartbeat(sample)

            if self._stop_requested:
                self.log.info("종료 요청 수신")

        finally:
            self.stop()

            if self.rpicam_log_handle is not None:
                self.rpicam_log_handle.close()
                self.rpicam_log_handle = None

            result = self._build_result()

            # 마지막 상태가 이상이면 실패로 처리합니다.
            # 중간에 발생했다가 회복된 경우는 성공으로 두되 이력에 남깁니다.
            if result.final_state is HealthState.STALLED:
                exit_code = 1

            self.reporter.on_finish(result.final_state)
            self.reporter.close()
            self._print_report(result)

            if self.file_log_handler is not None:
                logging.getLogger("walkcam").removeHandler(self.file_log_handler)
                self.file_log_handler.close()
                self.file_log_handler = None

        return exit_code


# ─────────────────────────────────────────────────────────


def setup_console_logging(verbose: bool) -> None:
    root = logging.getLogger("walkcam")
    root.setLevel(logging.DEBUG if verbose else logging.INFO)
    root.propagate = False

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(
        logging.Formatter("%(asctime)s [%(levelname)s] %(message)s",
                          datefmt="%H:%M:%S")
    )
    root.addHandler(handler)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="산책 영상 촬영 + 건강 판정 (v0.2)"
    )
    parser.add_argument("--duration", type=float, default=None,
                        help="녹화 시간(초). 생략하면 무한")
    parser.add_argument("--dry-run", action="store_true",
                        help="실행하지 않고 명령만 출력")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    setup_console_logging(args.verbose)
    log = logging.getLogger("walkcam")

    try:
        WalkCam.check_environment()
    except RuntimeError as e:
        log.error("%s", e)
        return 1

    cam = WalkCam(duration=args.duration)

    if args.dry_run:
        fake_dir = OUTPUT_DIR / "session_YYYYmmdd_HHMMSS"
        print(" ".join(cam.build_command(fake_dir)))
        return 0

    try:
        return cam.run()
    except Exception as e:
        log.exception("실행 중 오류: %s", e)
        return 1


if __name__ == "__main__":
    sys.exit(main())