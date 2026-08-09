#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
walkcam_key.py — 키 입력(SSH)으로 제어하는 촬영 데몬

포고핀 도킹 트리거(walkcam_dock.py)를 대체하는 단순화 버전입니다.
도킹 감시와 데이터 전송이 빠지고, 촬영 시작/종료를 명령 파이프로
받습니다. 촬영·화면·사운드 자산은 기존 것을 그대로 재사용합니다.

동작
    부팅(systemd)      → OLED에 ♥ 하트 (촬영하지 않음)
    "toggle" 명령 수신 → 촬영 시작 + undocked.wav 재생
    다시 "toggle"      → 촬영 종료 + docked.wav 재생 → ♥ 복귀
    영상은 ~/walk/session_*/ 에 저장만 하고 전송하지 않습니다.

명령 채널
    데몬이 명령 파이프(FIFO) /home/piw/walkcam/walkcam.cmd 를 만들어
    감시합니다. systemd 데몬은 터미널이 없어 키보드를 직접 못 받으므로,
    SSH에서 walkcam_ctl.py(키 리스너)를 실행해 파이프로 명령을 보냅니다.
    수동으로도 가능합니다:  echo toggle > ~/walkcam/walkcam.cmd

지원 명령
    toggle  촬영 시작/종료 반전
    start   촬영 시작 (이미 촬영 중이면 무시)
    stop    촬영 종료 (대기 중이면 무시)
    burst   대기 하트에서 6방향 하트 분출 (IDLE 화면 전용)
    beg     산책 조르기 화면 토글 (IDLE ↔ 조르기)
    clock   현재 시각 화면 토글 (IDLE ↔ 시계)
    greet   주인 마중 화면 토글 (IDLE ↔ 마중)
    quit    데몬 종료

사용법
    python3 walkcam_key.py            # 수동 실행
    (systemd 등록은 walkcam-key.service 참고)
"""

from __future__ import annotations

import argparse
import os
import queue
import signal
import subprocess
import sys
import threading
from pathlib import Path

from gpiozero import LED

from oled_status import OledStatusDisplay, ScreenState
from walkcam_button import LED_PIN, SessionState
from walkcam_oled import OledRecordingToggle, PanelReporter
from walkcam_v3 import CamConfig, WalkCam, setup_console_logging

CMD_FIFO = Path("/home/piw/walkcam/walkcam.cmd")
SOUND_DIR = Path("/home/piw/Sound_Play/sounds")
WALK_DIR = Path("/home/piw/walk")


def latest_walk_epoch() -> float | None:
    """가장 최근 세션 폴더의 수정 시각(epoch). 없으면 None."""
    try:
        sessions = list(WALK_DIR.glob("session_*"))
        if not sessions:
            return None
        return max(p.stat().st_mtime for p in sessions)
    except OSError:
        return None

LOG = None  # main()에서 설정


def play_sound(name: str) -> None:
    """확인음 재생 (논블로킹). 소리 실패가 본 흐름을 막으면 안 됩니다."""
    path = SOUND_DIR / name
    if not path.exists():
        if LOG:
            LOG.debug("사운드 파일 없음: %s", path)
        return
    try:
        subprocess.Popen(
            ["aplay", "-q", "-B", "500000", str(path)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    except Exception:
        if LOG:
            LOG.debug("사운드 재생 실패", exc_info=True)


class HeartPanelReporter(PanelReporter):
    """세션 종료 후 '산책 완료' 축하 화면을 거쳐 ♥ 하트로 복귀."""

    def on_finish(self, final_state) -> None:
        # 시계가 리셋되기 전에 이번 산책의 최종 경과 시간을 확보
        walked = self.display.ctx.elapsed() if self.display else 0.0
        super().on_finish(final_state)          # LED 정리 + 시계 리셋
        if not self.display:
            return
        if walked > 3.0:
            self.display.celebrate(walked)      # 축하 후 자동으로 ♥ 복귀
        else:
            # 시작 직후 취소된 초단타 세션은 축하 없이 바로 ♥
            self.display.set_state(ScreenState.IDLE)


class SoundToggle(OledRecordingToggle):
    """촬영 시작/종료 시점에 확인음을 얹은 토글.

    undocked.wav = 촬영 시작 (산책 출발음)
    docked.wav   = 촬영 종료
    """

    def _start(self) -> None:
        play_sound("undocked.wav")
        super()._start()

    def _request_stop(self) -> None:
        play_sound("docked.wav")
        super()._request_stop()      # OLED '저장 중' 전환 포함


def fifo_reader(fifo: Path, events: "queue.Queue[str]",
                stop_evt: threading.Event) -> None:
    """명령 파이프를 반복해서 열고 읽는 스레드.

    FIFO는 쓰는 쪽이 닫으면 EOF가 되므로, 루프에서 다시 엽니다.
    """
    while not stop_evt.is_set():
        try:
            with open(fifo, "r") as f:          # 쓰는 쪽이 생길 때까지 블록
                for line in f:
                    cmd = line.strip().lower()
                    if cmd:
                        events.put(cmd)
        except Exception:
            stop_evt.wait(1.0)


def main() -> int:
    global LOG
    parser = argparse.ArgumentParser(
        description="키 입력(SSH)으로 촬영을 제어합니다. 촬영·저장 전용."
    )
    parser.add_argument("--duration", type=float, default=None,
                        help="세션당 최대 녹화 시간(초). 생략하면 키로만 종료")
    parser.add_argument("--led-pin", type=int, default=LED_PIN)
    parser.add_argument("--no-oled", action="store_true")
    parser.add_argument("--no-rotate", action="store_true")
    parser.add_argument("--no-probe-camera", action="store_true")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    LOG = setup_console_logging(args.verbose)
    config = CamConfig()

    try:
        WalkCam.check_environment(config, probe_camera=not args.no_probe_camera)
    except RuntimeError as e:
        LOG.error("%s", e)
        return 1

    # 명령 파이프 준비
    if CMD_FIFO.exists() and not CMD_FIFO.is_fifo():
        CMD_FIFO.unlink()
    if not CMD_FIFO.exists():
        os.mkfifo(CMD_FIFO)

    display: OledStatusDisplay | None = None
    led: LED | None = None
    toggle: SoundToggle | None = None
    events: "queue.Queue[str]" = queue.Queue()
    stop_evt = threading.Event()

    try:
        # 화면: 부팅 즉시 ♥ 하트 (촬영하지 않음 — 요구사항 1)
        if not args.no_oled:
            try:
                display = OledStatusDisplay(rotate=not args.no_rotate)
                display.set_state(ScreenState.IDLE)
                display.start()
            except Exception:
                LOG.exception("OLED 초기화 실패 — LED만으로 계속합니다")
                display = None

        led = LED(args.led_pin)
        led.off()

        toggle = SoundToggle(
            HeartPanelReporter(led, display), LOG, config,
            duration=args.duration,
        )

        reader = threading.Thread(
            target=fifo_reader, args=(CMD_FIFO, events, stop_evt),
            name="cmd-fifo", daemon=True,
        )
        reader.start()

        signal.signal(signal.SIGTERM, lambda *_: events.put("quit"))

        LOG.info("준비 완료 — 명령 파이프: %s", CMD_FIFO)
        LOG.info("SSH에서 'python3 walkcam_ctl.py' 실행 후 스페이스/q로 토글")

        while True:
            cmd = events.get()
            if cmd == "toggle":
                toggle.on_press()               # 기존 버튼과 동일한 반전 동작
            elif cmd == "start":
                if toggle.state is SessionState.IDLE:
                    toggle.on_press()
            elif cmd == "stop":
                if toggle.state is SessionState.RECORDING:
                    toggle.on_press()
            elif cmd == "burst":
                if display and toggle.state is SessionState.IDLE:
                    display.heart_burst()
            elif cmd == "beg":
                if display and toggle.state is SessionState.IDLE:
                    if display.ctx.state is ScreenState.BEGGING:
                        display.set_state(ScreenState.IDLE)   # ♥ 복귀
                    else:
                        display.show_begging(latest_walk_epoch())
            elif cmd == "clock":
                if display and toggle.state is SessionState.IDLE:
                    if display.ctx.state is ScreenState.CLOCK:
                        display.set_state(ScreenState.IDLE)   # ♥ 복귀
                    else:
                        display.set_state(ScreenState.CLOCK)
            elif cmd == "greet":
                if display and toggle.state is SessionState.IDLE:
                    if display.ctx.state is ScreenState.GREETING:
                        display.set_state(ScreenState.IDLE)   # ♥ 복귀
                    else:
                        display.set_state(ScreenState.GREETING)
            elif cmd == "quit":
                LOG.info("종료 명령 수신")
                break
            else:
                LOG.debug("알 수 없는 명령 무시: %r", cmd)

        return 0

    except KeyboardInterrupt:
        LOG.info("중단 요청 수신")
        return 0

    finally:
        stop_evt.set()
        if toggle is not None:
            toggle.shutdown()
        if led is not None:
            led.off()
            led.close()
        if display is not None:
            display.close()


if __name__ == "__main__":
    sys.exit(main())
