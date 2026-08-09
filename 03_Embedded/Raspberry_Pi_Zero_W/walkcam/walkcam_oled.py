#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
walkcam_oled.py — 버튼 토글 + LED + OLED 상태 표시 런처

walkcam_button.py의 토글 로직(RecordingToggle)을 그대로 재사용하고,
LED 리포터를 OLED까지 함께 갱신하는 PanelReporter로 바꿔 끼운 것이
이 파일의 전부입니다. 촬영·판정 로직은 walkcam_v3.py에 있습니다.

계층 구조
    ssd1309.py       OLED 하드웨어 드라이버
    oled_status.py   상태 화면 렌더링 (백그라운드 스레드)
    walkcam_v3.py    촬영 + 건강 판정
    walkcam_button.py  버튼 토글 상태 기계 (재사용)
    walkcam_oled.py  ← 이 파일. 전부 조립하는 진입점

동작
    프로그램 시작   → OLED 전원 ON, "촬영 대기" 표시
    버튼 1회        → "카메라 준비 중" (경과 시계 시작)
    파일이 자라면   → "● REC mm:ss" (초 단위 갱신)
    데이터 정체     → "데이터 정체!" 반전 점멸
    버튼 2회        → "저장 중..." → 정리 후 다시 "촬영 대기"
    Ctrl+C          → 세션 정리 후 OLED 소등, 프로그램 종료

상태 판정의 근거는 LED와 완전히 같습니다(HealthMonitor). 즉 LED 점등
고정과 OLED의 REC 표시는 같은 사건("파일이 실제로 자라고 있다")입니다.

배선
    버튼: 물리 11 (GPIO17) ↔ GND (물리 9)
    LED : 물리 13 (GPIO27) → 220~330Ω → LED → GND (물리 6)
    OLED: DC GPIO24, RST GPIO25, SPI0 (MOSI 10 / SCLK 11 / CE0 8)

사용법
    python3 walkcam_oled.py
    python3 walkcam_oled.py --keyboard        # 버튼 없이 Enter로 토글
    python3 walkcam_oled.py --duration 1800   # 세션당 최대 30분
    python3 walkcam_oled.py --no-oled         # OLED 없이 (walkcam_button과 동일)
"""

from __future__ import annotations

import argparse
import signal
import sys
import threading
from pathlib import Path

from gpiozero import LED, Button

from oled_status import OledStatusDisplay, ScreenState
from walkcam_button import (
    BOUNCE_TIME,
    BUTTON_PIN,
    LED_PIN,
    LedReporter,
    RecordingToggle,
    run_keyboard_mode,
)
from walkcam_v3 import (
    CamConfig,
    HealthSample,
    HealthState,
    WalkCam,
    setup_console_logging,
)


class PanelReporter(LedReporter):
    """LED 패턴과 OLED 화면을 함께 갱신하는 리포터.

    LedReporter를 상속하는 이유: RecordingToggle이 리포터의 .led 속성과
    indicate_starting()을 직접 사용하므로, 그 계약을 그대로 유지하면서
    OLED 갱신만 얹는 것이 가장 침습이 적습니다.

    display가 None이면 LED 단독으로 동작합니다(--no-oled).
    close()는 LedReporter처럼 비워 둡니다 — OLED의 소유자는 런처이고,
    세션이 끝나도 화면은 "촬영 대기"로 돌아가 계속 켜져 있어야 합니다.
    """

    def __init__(self, led: LED, display: OledStatusDisplay | None):
        super().__init__(led)
        self.display = display

    # 버튼이 눌린 직후 (RecordingToggle._start가 호출)
    def indicate_starting(self) -> None:
        super().indicate_starting()
        if self.display:
            self.display.session_starting()

    # 세션 디렉토리가 만들어지고 rpicam-vid가 뜬 시점
    def on_start(self, session_dir: Path) -> None:
        if self.display:
            self.display.set_state(ScreenState.STARTING)

    def on_state_change(self, sample: HealthSample) -> None:
        super().on_state_change(sample)
        if not self.display:
            return
        if sample.state is HealthState.RECORDING:
            self.display.set_state(ScreenState.RECORDING)
        elif sample.state is HealthState.STALLED:
            self.display.set_state(ScreenState.STALLED)
        else:
            self.display.set_state(ScreenState.STARTING)

    def on_heartbeat(self, sample: HealthSample) -> None:
        if self.display:
            self.display.update_stats(sample.segment_count, sample.free_mb)

    def on_finish(self, final_state: HealthState) -> None:
        super().on_finish(final_state)
        if self.display:
            self.display.session_finished()


class OledRecordingToggle(RecordingToggle):
    """종료 요청 즉시 '저장 중' 화면으로 전환하기 위한 얇은 확장.

    on_finish는 정리가 끝난 뒤에야 오므로, 버튼을 눌러 종료를 요청한
    순간과 실제 종료 사이(stop_timeout까지)의 구간을 표시하려면
    _request_stop 시점을 가로채야 합니다.
    """

    def _request_stop(self) -> None:
        reporter = self.led_reporter
        if isinstance(reporter, PanelReporter) and reporter.display:
            reporter.display.set_state(ScreenState.STOPPING)
        super()._request_stop()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="버튼 토글 + OLED 상태 표시로 산책 영상을 녹화합니다."
    )
    parser.add_argument("--button-pin", type=int, default=BUTTON_PIN,
                        help=f"버튼 GPIO 번호(BCM). 기본 {BUTTON_PIN}")
    parser.add_argument("--led-pin", type=int, default=LED_PIN,
                        help=f"LED GPIO 번호(BCM). 기본 {LED_PIN}")
    parser.add_argument("--duration", type=float, default=None,
                        help="세션당 최대 녹화 시간(초). 생략하면 버튼으로만 종료")
    parser.add_argument("--keyboard", action="store_true",
                        help="버튼 대신 Enter로 토글(배선 문제 격리용)")
    parser.add_argument("--no-oled", action="store_true",
                        help="OLED 없이 LED만 사용")
    parser.add_argument("--no-rotate", action="store_true",
                        help="OLED를 180도 회전 없이 원래 방향으로 출력")
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

    led: LED | None = None
    button: Button | None = None
    toggle: RecordingToggle | None = None
    display: OledStatusDisplay | None = None
    shutdown = threading.Event()

    try:
        # OLED를 가장 먼저 켭니다. 초기화에 실패해도(배선 문제 등)
        # 녹화 자체는 가능해야 하므로 경고만 남기고 계속 갑니다.
        if not args.no_oled:
            try:
                display = OledStatusDisplay(rotate=not args.no_rotate)
                display.start()  # 이 순간부터 "촬영 대기"가 표시됩니다
                if not display.ctx.korean:
                    log.warning(
                        "한글 폰트가 없어 OLED는 영문으로 표시됩니다. "
                        "설치: sudo apt install fonts-nanum"
                    )
            except Exception:
                log.exception("OLED 초기화 실패 — LED만으로 계속합니다")
                display = None

        led = LED(args.led_pin)
        led.off()

        toggle = OledRecordingToggle(
            PanelReporter(led, display), log, config, duration=args.duration
        )

        signal.signal(signal.SIGTERM, lambda *_: shutdown.set())

        if args.keyboard:
            run_keyboard_mode(toggle, log, shutdown)
        else:
            button = Button(
                args.button_pin,
                pull_up=True,
                bounce_time=BOUNCE_TIME,
            )
            button.when_pressed = toggle.on_press

            log.info("준비 완료  (버튼 GPIO%d / LED GPIO%d / OLED %s)",
                     args.button_pin, args.led_pin,
                     "켜짐" if display else "없음")
            log.info("버튼을 누르면 녹화가 시작됩니다. 프로그램 종료는 Ctrl+C")
            shutdown.wait()

        log.info("종료 신호 수신")
        return 0

    except KeyboardInterrupt:
        log.info("중단 요청 수신")
        return 0

    finally:
        if toggle is not None:
            toggle.shutdown()
        if button is not None:
            button.close()
        if led is not None:
            led.off()
            led.close()
        if display is not None:
            display.close()  # 화면을 지우고 패널 전원까지 내립니다


if __name__ == "__main__":
    sys.exit(main())
