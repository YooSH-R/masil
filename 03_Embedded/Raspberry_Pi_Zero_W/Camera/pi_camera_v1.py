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
    python3 walkcam_v01.py                 # 무한 녹화, Ctrl+C로 종료
    python3 walkcam_v01.py --duration 30   # 30초 녹화
    python3 walkcam_v01.py --dry-run       # 실행 없이 명령만 출력
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

# 실행 환경에 따라 HOME이 없을 수 있으므로 명시적으로 처리합니다.
OUTPUT_DIR = Path(os.environ.get("WALKCAM_OUTPUT", Path.home() / "walk"))

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

    def _create_session_dir(self) -> Path:
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        session_dir = OUTPUT_DIR / f"session_{stamp}"
        session_dir.mkdir(parents=True, exist_ok=True)
        return session_dir

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
        fake_dir = OUTPUT_DIR / "session_YYYYmmdd_HHMMSS"
        print(" ".join(cam.build_command(fake_dir)))
        return 0

    try:
        return cam.run()
    except Exception as e:
        print(f"오류: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())