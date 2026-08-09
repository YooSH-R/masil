#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
walkcam_dock.py — 도킹 트리거로 녹화·전송을 자동화하는 런처

버튼(walkcam_button.py) 자리에 dock_monitor를 꽂은 것이 이 파일의
전부입니다. 촬영은 walkcam_v3, 화면은 oled_status, 토글 상태 기계와
OLED 리포터는 walkcam_oled의 것을 그대로 재사용합니다.

동작 (사용자 시나리오 그대로)
    부팅            → ♥ 하트 대기 화면 (도킹 상태)
    독에서 분리     → "카메라 준비 중" → "● REC mm:ss"
    독에 도킹       → "저장 중..." → "전송 중..." (transfer_walks.sh)
    전송 완료       → ♥ 하트 대기 화면 복귀

상태 판정은 dock_monitor v2 (UDC configured + Jetson ping 하이브리드,
히스테리시스)를 그대로 씁니다. 배터리-VBUS 구조에서 분리를 감지하는
유일하게 신뢰 가능한 방법입니다.

자가 회복
    산책 중 rpicam이 죽어 세션이 끝나면, 여전히 미도킹 상태인 것을
    메인 루프가 감지하고 잠시 후 새 세션을 자동으로 시작합니다.
    "찍히는 줄 알았는데 안 찍혔다"를 막기 위한 안전망입니다.

전송 소유권
    전송은 이 런처가 직접 실행하고 완료를 기다립니다(화면 전환 때문).
    NM dispatcher 훅(90-walk-transfer)을 함께 두면 flock 경쟁으로
    이 런처의 실행이 즉시 반환되어 하트로 너무 일찍 돌아갑니다.
    → dispatcher 훅은 제거하세요:
        sudo rm /etc/NetworkManager/dispatcher.d/90-walk-transfer

전환기 옵션
    --with-button : 기존 버튼(GPIO17)도 병행 사용. 도킹 트리거가
                    신뢰를 얻으면 이 옵션과 배선을 제거하면 됩니다.

사용법
    python3 walkcam_dock.py                # 실제 운용
    python3 walkcam_dock.py --with-button  # 버튼 병행 (전환기)
    python3 walkcam_dock.py -v             # 자세한 로그
"""

from __future__ import annotations

import argparse
import os
import queue
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

from gpiozero import LED, Button

from dock_monitor import DockConfig, DockMonitor
from oled_status import OledStatusDisplay, ScreenState
from walkcam_button import (
    BOUNCE_TIME,
    BUTTON_PIN,
    LED_PIN,
    SessionState,
)
from walkcam_oled import OledRecordingToggle, PanelReporter
from walkcam_v3 import CamConfig, WalkCam, setup_console_logging

# 전송 스크립트 기본 위치
TRANSFER_SCRIPT = "/home/piw/walkcam/transfer_walks.sh"

# 세션이 스스로 죽었을 때(미도킹 상태) 재시작까지의 대기 시간.
# 즉시 재시작하면 카메라 하드웨어 문제 시 무한 재시작 폭주가 됩니다.
RESTART_COOLDOWN = 15.0

# 확인음 파일 위치
SOUND_DIR = Path("/home/piw/Sound_Play/sounds")


def play_sound(name: str, log) -> None:
    """확인음 재생 (논블로킹). 소리 실패가 본 흐름을 막으면 안 됩니다."""
    path = SOUND_DIR / name
    if not path.exists():
        log.debug("사운드 파일 없음: %s", path)
        return
    try:
        subprocess.Popen(
            ["aplay", "-q", str(path)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    except Exception:
        log.debug("사운드 재생 실패", exc_info=True)


class DockRecordingToggle(OledRecordingToggle):
    """버튼 토글을 도킹 이벤트용 명시적 시작/종료로 확장.

    버튼은 '누름 = 반전'이지만 도킹 이벤트는 방향이 명확합니다
    (분리 = 시작, 도킹 = 종료). 상태가 이미 맞으면 조용히 무시하므로
    중복 이벤트에도 안전합니다.
    """

    def start_session(self) -> None:
        with self._lock:
            if self._state is SessionState.IDLE:
                self._start()

    def stop_session(self) -> None:
        with self._lock:
            if self._state is SessionState.RECORDING:
                self._request_stop()


def _terminate_tree(proc: subprocess.Popen, log) -> None:
    """전송 스크립트와 그 자식(rsync)까지 프로세스 그룹째 종료합니다."""
    try:
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        log.warning("전송 프로세스가 5초 내 종료되지 않아 강제 종료합니다")
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    except ProcessLookupError:
        pass


def main() -> int:
    parser = argparse.ArgumentParser(
        description="도킹 트리거로 산책 영상 녹화와 전송을 자동화합니다."
    )
    parser.add_argument("--transfer-script", default=TRANSFER_SCRIPT,
                        help=f"도킹 시 실행할 전송 스크립트. 기본 {TRANSFER_SCRIPT}")
    parser.add_argument("--undock-confirm", type=float, default=2.0,
                        help="분리 확정에 필요한 연속 실패 시간(초). 기본 2.0")
    parser.add_argument("--dock-confirm", type=float, default=3.0,
                        help="도킹 확정에 필요한 연속 성공 시간(초). 기본 3.0")
    parser.add_argument("--duration", type=float, default=None,
                        help="세션당 최대 녹화 시간(초). 생략하면 도킹으로만 종료")
    parser.add_argument("--with-button", action="store_true",
                        help="기존 버튼(GPIO17)도 병행 사용 (전환기용)")
    parser.add_argument("--led-pin", type=int, default=LED_PIN)
    parser.add_argument("--button-pin", type=int, default=BUTTON_PIN)
    parser.add_argument("--no-oled", action="store_true",
                        help="OLED 없이 LED만 사용")
    parser.add_argument("--no-rotate", action="store_true",
                        help="OLED 180도 회전 없이 출력")
    parser.add_argument("--no-probe-camera", action="store_true",
                        help="시작 전 카메라 감지 확인을 생략")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    log = setup_console_logging(args.verbose)
    config = CamConfig()

    try:
        WalkCam.check_environment(config, probe_camera=not args.no_probe_camera)
    except RuntimeError as e:
        log.error("%s", e)
        return 1

    script = Path(args.transfer_script)
    if not (script.exists() and os.access(script, os.X_OK)):
        log.error("전송 스크립트가 없거나 실행 권한이 없습니다: %s", script)
        log.error("확인: chmod +x %s", script)
        return 1

    display: OledStatusDisplay | None = None
    led: LED | None = None
    button: Button | None = None
    toggle: DockRecordingToggle | None = None
    monitor: DockMonitor | None = None
    transfer_proc: subprocess.Popen | None = None

    events: "queue.Queue[str]" = queue.Queue()
    shutdown = threading.Event()
    last_session_end = 0.0
    prev_toggle_state = SessionState.IDLE

    try:
        # ── 화면: 가장 먼저 하트를 띄웁니다 ─────────────────
        if not args.no_oled:
            try:
                display = OledStatusDisplay(rotate=not args.no_rotate)
                display.set_state(ScreenState.IDLE)   # ♥
                display.start()
            except Exception:
                log.exception("OLED 초기화 실패 — LED만으로 계속합니다")
                display = None

        led = LED(args.led_pin)
        led.off()

        toggle = DockRecordingToggle(
            PanelReporter(led, display), log, config, duration=args.duration
        )

        # ── 도킹 감시: 이벤트를 큐로만 넘기고 즉시 반환 ────
        monitor = DockMonitor(
            on_dock=lambda: events.put("dock"),
            on_undock=lambda: events.put("undock"),
            config=DockConfig(
                undock_confirm_s=args.undock_confirm,
                dock_confirm_s=args.dock_confirm,
            ),
        )
        monitor.start()

        # ── (전환기) 버튼 병행 ──────────────────────────────
        if args.with_button:
            button = Button(args.button_pin, pull_up=True,
                            bounce_time=BOUNCE_TIME)
            button.when_pressed = toggle.on_press
            log.info("전환기 모드: 버튼(GPIO%d)도 함께 동작합니다",
                     args.button_pin)

        signal.signal(signal.SIGTERM, lambda *_: events.put("shutdown"))

        log.info("준비 완료 — 도킹 상태 판정을 기다립니다 "
                 "(분리 확정 %.1fs / 도킹 확정 %.1fs)",
                 args.undock_confirm, args.dock_confirm)

        # ── 메인 루프: 이벤트를 순서대로 처리 ──────────────
        while not shutdown.is_set():
            try:
                ev = events.get(timeout=0.5)
            except queue.Empty:
                ev = None

            # 전송 완료 감시: 끝났으면 하트로 복귀
            if transfer_proc is not None and transfer_proc.poll() is not None:
                rc = transfer_proc.returncode
                transfer_proc = None
                if rc == 0:
                    log.info("전송 완료 — 대기 화면으로 복귀")
                else:
                    log.warning("전송 스크립트 종료 코드 %d — 다음 도킹 때 이어받기", rc)
                    play_sound("warning.wav", log)
                if display:
                    display.set_state(ScreenState.IDLE)   # ♥

            if ev == "undock":
                log.info("[분리 확정] 산책 시작")
                # 전송 도중 들고 나가면 전송을 끊고 녹화를 우선합니다.
                # rsync --partial 덕에 다음 도킹 때 이어받습니다.
                if transfer_proc is not None:
                    log.info("전송 중단(미완료분은 다음 도킹 때 이어받기)")
                    _terminate_tree(transfer_proc, log)
                    transfer_proc = None
                toggle.start_session()

            elif ev == "dock":
                log.info("[도킹 확정] 녹화 종료 및 전송 시작")
                play_sound("docked.wav", log)
                if toggle.state is SessionState.RECORDING:
                    toggle.stop_session()
                    # 세션 정리(최대 stop_timeout)를 기다립니다.
                    deadline = time.monotonic() + config.stop_timeout + 10.0
                    while (toggle.state is not SessionState.IDLE
                           and time.monotonic() < deadline):
                        time.sleep(0.2)

                if transfer_proc is None:
                    if display:
                        display.set_state(ScreenState.TRANSFERRING)
                    # 프로세스 그룹으로 띄워 중단 시 rsync까지 정리 가능하게
                    transfer_proc = subprocess.Popen(
                        ["/bin/bash", str(script)],
                        start_new_session=True,
                    )

            elif ev == "shutdown":
                log.info("종료 신호 수신")
                shutdown.set()

            # 자가 회복: 미도킹인데 세션이 없으면(중간에 죽음) 재시작.
            # 세션이 RECORDING → IDLE로 '방금' 전이한 시각을 기록해 두고,
            # 쿨다운이 지나도록 여전히 미도킹+무세션이면 다시 시작합니다.
            cur = toggle.state
            if prev_toggle_state is SessionState.RECORDING and cur is SessionState.IDLE:
                last_session_end = time.monotonic()
            prev_toggle_state = cur

            if (ev is None
                    and monitor.state == DockMonitor.UNDOCKED
                    and cur is SessionState.IDLE
                    and transfer_proc is None
                    and time.monotonic() - last_session_end > RESTART_COOLDOWN):
                log.warning("미도킹 상태에서 세션이 없습니다 — 녹화 재시작")
                last_session_end = time.monotonic()
                toggle.start_session()

        return 0

    except KeyboardInterrupt:
        log.info("중단 요청 수신")
        return 0

    finally:
        if transfer_proc is not None:
            _terminate_tree(transfer_proc, log)
        if toggle is not None:
            toggle.shutdown()
        if monitor is not None:
            monitor.request_stop()
        if button is not None:
            button.close()
        if led is not None:
            led.off()
            led.close()
        if display is not None:
            display.close()


if __name__ == "__main__":
    sys.exit(main())
