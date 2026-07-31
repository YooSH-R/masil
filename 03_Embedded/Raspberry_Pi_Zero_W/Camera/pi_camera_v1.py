#!/usr/bin/env python3
"""
walkcam_v01.py - 산책 영상 촬영 베이스라인

버전: v0.1
목적: 최소 기능의 안정적인 녹화 골격. 페인 포인트 대응은 이후 버전에서 단계적으로 추가.

현재 구현 범위
    - rpicam-vid 구동 및 세그먼트 녹화
    - Ctrl+C / SIGTERM 안전 종료
    - 세션 디렉터리 관리
    - rpicam-vid 로그를 파일로 보존

의도적으로 제외한 것 (이후 버전에서 추가)
    - v0.2  LED 상태 표시            (내7 관측 불가)
    - v0.3  워치독 / 무응답 탐지      (내8, 내6)
    - v0.4  디스크·전원 감시          (내5, 내9)
    - v0.5  시계 앵커 및 메타데이터   (내2)

사용법
    python3 pi_camera_v1.py                 # 무한 녹화, Ctrl+C로 종료
    python3 pi_camera_v1.py --duration 30   # 30초 녹화
    python3 pi_camera_v1.py --dry-run       # 실행 없이 명령만 출력
"""

from __future__ import annotations

import argparse
import os
import shutil
import signal
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

# ─────────────────────────────────────────────────────────
# 설정
# ─────────────────────────────────────────────────────────

# [변경 전] 실행 환경에 따라 HOME이 없을 수 있으므로 명시적으로 처리합니다.
# OUTPUT_DIR = Path(os.environ.get("WALKCAM_OUTPUT", Path.home() / "walk"))
#
# [변경 사유]
# 위 코드는 모듈을 import하는 순간(스크립트 최상단, 함수 호출 이전)에 즉시 실행됩니다.
# Path.home()은 HOME 환경변수도 없고 pwd 데이터베이스에서도 사용자를 찾지 못하면
# RuntimeError를 던지는데, 이 시점은 argparse도, --dry-run 분기도, 아래
# check_environment()의 "친절한 오류 메시지 출력 후 정상 종료(return 1)" 경로도
# 전혀 거치지 못한 시점입니다. 즉 import만 해도 트레이스백과 함께 통째로 죽습니다.
#
# [변경 방식]
# Path.home() 평가를 모듈 로드 시점에서 "실제로 경로가 필요한 시점"까지 지연시킵니다.
# 1) WALKCAM_OUTPUT 환경변수가 있으면 Path.home()을 아예 호출하지 않고 그 값을 그대로 씁니다.
# 2) 없을 때만 Path.home()을 호출하되 try/except로 감싸서, 실패 시 원인이 뭔지도 모른 채
#    죽는 대신 "WALKCAM_OUTPUT을 지정하라"는 실행 가능한 안내가 담긴 RuntimeError로 바꿔줍니다.
# 3) 이 함수는 정의만 되고 즉시 호출되지 않으므로, import 시점에는 아무 부작용이 없습니다.
#    실제 호출은 check_environment()(사전 점검 시점, main 함수 참고)와
#    _create_session_dir()(실제 디렉터리 생성 시점)에서 이루어집니다.
def resolve_output_dir() -> Path:
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

# 1296x972 = OV5647 전체 화각 모드.
# 1920x1080을 쓰면 센서 면적의 41%만 사용되어 화각이 좁아집니다.
SENSOR_MODE = "1296:972"
WIDTH = 1296
HEIGHT = 972

FRAMERATE = 15
BITRATE = 3_000_000       # 3Mbps, 약 1.35 GB/시간
SEGMENT_MS = 300_000      # 5분 분할

EXPOSURE = "sport"        # 보행 중 모션 블러 억제
DENOISE = "cdn_fast"

# rpicam-vid 로그 상세도.
# 1로 두면 프레임 단위 로그가 남아 이후 워치독 구현 시 활용 가능합니다.
# 2시간 기준 로그 크기는 5~10MB 수준입니다.
VERBOSITY = 1

STOP_TIMEOUT = 15.0       # 종료 신호 후 대기 시간(초)
POLL_INTERVAL = 0.5


# ─────────────────────────────────────────────────────────


class WalkCam:
    """rpicam-vid 프로세스의 생애주기를 관리합니다."""

    def __init__(self, duration: float | None = None):
        self.duration = duration
        self.proc: subprocess.Popen | None = None
        self.session_dir: Path | None = None
        self.log_handle = None
        self.started_at: float | None = None
        self._stop_requested = False

    # ── 준비 ─────────────────────────────────────────────

    @staticmethod
    def check_environment() -> None:
        """실행 전 필수 조건을 확인합니다. 실패 시 예외를 발생시킵니다."""
        if shutil.which("rpicam-vid") is None:
            raise RuntimeError(
                "rpicam-vid를 찾을 수 없습니다. "
                "rpicam-apps가 설치되어 있는지 확인하세요."
            )

        # [추가] resolve_output_dir()도 여기서 함께 검증합니다.
        # rpicam-vid 부재를 검사하는 방식(shutil.which 결과가 None이면 예외)과
        # 동일한 패턴으로, "사전 점검은 check_environment()에 모은다"는 기존 구조를
        # 그대로 따릅니다. 반환값은 여기서 쓰지 않고 버립니다 — 목적은 저장 경로를
        # 구하는 것이 아니라 "나중에 _create_session_dir()에서 터지지 않을지"를
        # main()의 사전 점검 단계에서 미리 확인하는 것입니다. 실패하면 RuntimeError가
        # main()의 기존 except 블록(line 296-300)에서 그대로 잡혀 친절한 오류 메시지로
        # 출력되고 정상적으로 return 1 됩니다.
        resolve_output_dir()

    def _create_session_dir(self) -> Path:
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        # [변경 전] session_dir = OUTPUT_DIR / f"session_{stamp}"
        # [변경 사유] OUTPUT_DIR은 모듈 임포트 시점에 평가되는 전역 상수였습니다.
        # [변경 방식] 실제로 디렉터리를 만드는 "이 시점"에 resolve_output_dir()을
        #             호출해 지연 평가합니다. check_environment()에서 이미 한 번
        #             검증을 통과했더라도, 혹시 모를 실패 시 여기서도 동일한
        #             RuntimeError로 안전하게 실패합니다.
        #
        # [변경 전] session_dir = resolve_output_dir() / f"session_{stamp}"
        #           session_dir.mkdir(parents=True, exist_ok=True)
        #           return session_dir
        #
        # [변경 사유] Docs.md/PainPoint.md의 내2(RTC 부재)에 정리된 대로, Zero W는
        # 배터리 백업 RTC가 없어 네트워크 없이 야외에서 재부팅하면 시스템 시각이
        # 과거의 특정 시점으로 되돌아가거나 고정될 수 있습니다. 이 상태로 재부팅을
        # 반복하며 여러 번 녹화하면 datetime.now() 기반 이름("session_20260101_000000"
        # 등)이 서로 다른 세션에서 동일하게 생성될 수 있습니다. 기존에는 mkdir이
        # exist_ok=True였기 때문에 이 경우 새 세션이 기존 디렉터리를 그대로
        # 재사용했고, rpicam-vid는 항상 seg_0000.h264부터 번호를 다시 매기므로
        # 이전 세션의 세그먼트 파일을 덮어써 데이터가 손실됩니다.
        #
        # [변경 방식] mkdir을 exist_ok=False로 호출해 "이미 존재하는 디렉터리에는
        # 절대 쓰지 않는다"를 원칙으로 삼습니다. 대상 디렉터리가 이미 있으면
        # FileExistsError를 잡아 이름 뒤에 _001, _002 ... 순차 번호를 붙여가며
        # 존재하지 않는 이름을 찾을 때까지 재시도합니다. parents=True는 유지하므로
        # 상위 디렉터리(예: ~/walk)가 이미 있는 것은 문제되지 않고, 오직 최종
        # session_* 디렉터리 자체의 충돌만 막습니다. 이렇게 하면 시스템 시각이
        # 틀려도 세션끼리 파일이 섞이는 일은 없고, 디렉터리 이름이 겹쳤다는 사실
        # 자체가 "이 세션은 시각이 어긋나 있었다"는 단서로 남습니다.
        output_dir = resolve_output_dir()
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

    def build_command(self, session_dir: Path) -> list[str]:
        """rpicam-vid 실행 명령을 조립합니다.

        주의: --segment 사용 시 출력 경로에 반드시 형식 지정자(%04d)가
        있어야 합니다. 없으면 rpicam-vid가 같은 파일을 계속 덮어씁니다.
        """
        output_pattern = str(session_dir / "seg_%04d.h264")

        return [
            "rpicam-vid",
            "--nopreview",
            "--timeout", "0",              # 무한. 종료는 Python이 신호로 제어
            "--mode", SENSOR_MODE,
            "--width", str(WIDTH),
            "--height", str(HEIGHT),
            "--framerate", str(FRAMERATE),
            "--codec", "h264",
            "--bitrate", str(BITRATE),
            "--intra", str(FRAMERATE),     # 1초마다 키프레임
            "--inline",                    # 세그먼트 독립 디코딩에 필수
            "--flush",                     # 전원 손실 시 손실 최소화
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
        # 핸들러 안에서는 플래그만 세웁니다.
        # 실제 종료 처리는 메인 루프가 담당합니다.
        self._stop_requested = True

    # ── 실행 ─────────────────────────────────────────────

    def start(self) -> None:
        self.session_dir = self._create_session_dir()
        log_path = self.session_dir / "rpicam.log"

        cmd = self.build_command(self.session_dir)

        print(f"세션 디렉터리 : {self.session_dir}")
        print(f"로그 파일     : {log_path}")
        print(f"설정          : {WIDTH}x{HEIGHT} @ {FRAMERATE}fps, "
              f"{BITRATE // 1_000_000}Mbps, {SEGMENT_MS // 1000}초 분할")
        print()

        # stderr를 파일로 보냅니다.
        # subprocess.PIPE를 쓰고 읽지 않으면 파이프 버퍼(약 64KB)가 차서
        # rpicam-vid가 블로킹됩니다. 장시간 녹화에서 반드시 발생합니다.
        self.log_handle = log_path.open("wb")

        try:
            self.started_at = time.monotonic()
            self.proc = subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=self.log_handle,
                start_new_session=True,
            )
        except Exception:
            self.log_handle.close()
            self.log_handle = None
            raise

        print(f"녹화 시작 (PID {self.proc.pid})")

    def stop(self) -> None:
        """rpicam-vid가 현재 세그먼트를 정상적으로 닫도록 유도합니다."""
        if self.proc is None or self.proc.poll() is not None:
            return

        print("종료 신호 전송...")
        try:
            self.proc.send_signal(signal.SIGINT)
        except ProcessLookupError:
            return

        try:
            self.proc.wait(timeout=STOP_TIMEOUT)
            print("정상 종료됨")
        except subprocess.TimeoutExpired:
            print(f"{STOP_TIMEOUT:.0f}초 내 응답 없음 → 강제 종료")
            self.proc.kill()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                print("경고: 프로세스가 종료되지 않았습니다")

    def _report(self) -> None:
        if self.session_dir is None:
            return

        segments = sorted(self.session_dir.glob("seg_*.h264"))
        total = sum(s.stat().st_size for s in segments)
        elapsed = time.monotonic() - self.started_at if self.started_at else 0.0

        print()
        print("─" * 50)
        print(f"녹화 시간   : {elapsed:.1f}초 ({elapsed / 60:.1f}분)")
        print(f"세그먼트    : {len(segments)}개")
        print(f"총 용량     : {total / 1024 / 1024:.1f} MB")
        if elapsed > 0:
            print(f"실효 비트레이트: {total * 8 / elapsed / 1_000_000:.2f} Mbps")
        print(f"저장 위치   : {self.session_dir}")
        print("─" * 50)

        if not segments:
            print()
            print("경고: 생성된 세그먼트가 없습니다.")
            print(f"      로그를 확인하세요: {self.session_dir / 'rpicam.log'}")

    def run(self) -> int:
        self._install_handlers()
        self.start()

        exit_code = 0

        try:
            while not self._stop_requested:
                returncode = self.proc.poll()
                if returncode is not None:
                    print(f"rpicam-vid가 스스로 종료되었습니다 (rc={returncode})")
                    if returncode != 0:
                        exit_code = 1
                    break

                if self.duration is not None:
                    if (time.monotonic() - self.started_at) >= self.duration:
                        print(f"지정 시간({self.duration}초) 도달")
                        break

                time.sleep(POLL_INTERVAL)

            if self._stop_requested:
                print("\n종료 요청 수신")

        finally:
            self.stop()
            if self.log_handle is not None:
                self.log_handle.close()
                self.log_handle = None
            self._report()

        return exit_code


# ─────────────────────────────────────────────────────────


def main() -> int:
    parser = argparse.ArgumentParser(
        description="산책 영상 촬영 (v0.1 베이스라인)"
    )
    parser.add_argument(
        "--duration", type=float, default=None,
        help="녹화 시간(초). 생략하면 Ctrl+C까지 무한 녹화",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="실행하지 않고 조립된 명령만 출력",
    )
    args = parser.parse_args()

    try:
        WalkCam.check_environment()
    except RuntimeError as e:
        print(f"오류: {e}", file=sys.stderr)
        return 1

    cam = WalkCam(duration=args.duration)

    if args.dry_run:
        # [변경 전] fake_dir = OUTPUT_DIR / "session_YYYYmmdd_HHMMSS"
        # [변경 사유] 위와 동일하게 모듈 전역 상수 OUTPUT_DIR을 참조하던 부분입니다.
        # [변경 방식] resolve_output_dir()로 대체합니다. 이 시점은 이미 위쪽의
        #             check_environment() 호출(line 296-300)을 통과한 뒤이므로
        #             정상적인 경우 여기서 새로 실패할 일은 없습니다. dry-run은
        #             디스크에 실제로 쓰지 않으므로 mkdir은 호출하지 않습니다.
        fake_dir = resolve_output_dir() / "session_YYYYmmdd_HHMMSS"
        print(" ".join(cam.build_command(fake_dir)))
        return 0

    try:
        return cam.run()
    except Exception as e:
        print(f"오류: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())