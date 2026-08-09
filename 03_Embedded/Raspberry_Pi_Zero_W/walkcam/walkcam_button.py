#!/usr/bin/env python3
"""
walkcam_button.py — 버튼 토글로 녹화를 시작/종료하는 런처

walkcam_v3.py를 import해서 사용합니다. 촬영과 판정 로직은 전부 그쪽에 있고,
이 파일은 "언제 시작하고 언제 멈출지"와 "LED로 어떻게 보여줄지"만 담당합니다.

v3와의 관계
    v0.2 시절에는 run()이 내부에서 signal.signal()을 부르고 종료 경로가
    비공개 깃발이어서, 런처가 WalkCam을 상속해 내부를 우회해야 했습니다.
    v3는 run(install_signal_handlers=False)와 request_stop()을 공개하므로
    상속이나 우회 없이 그대로 씁니다.

동작
    버튼 1회 → 녹화 시작
    버튼 2회 → 녹화 종료
    Ctrl+C   → 녹화 중이면 안전하게 종료한 뒤 프로그램 종료

LED 표시
    느린 점멸 (0.5초) : 준비 중 — 프로세스는 떴지만 파일이 아직 안 자람
    점등 고정         : 정상 녹화 — 파일이 실제로 자라고 있음
    빠른 점멸 (0.1초) : 이상 — 데이터 정체 (케이블 / 카메라 / 디스크)
    소등              : 대기 또는 종료

    "버튼이 눌렸다"와 "실제로 녹화되고 있다"를 구분하는 것이 핵심입니다.
    카메라 초기화에 수 초가 걸리고, 리본 케이블이 헐거우면 프로세스는 떠도
    파일이 자라지 않습니다. 점등이 고정되는 순간이 곧 "결과물이 나오고 있다"는
    확인입니다. 단순한 켜짐/꺼짐만 원하면 아래 LED_PATTERNS를 고치세요.

배선
    버튼: 한쪽 -> 물리 11번 (GPIO17),  다른쪽 -> GND (물리 9번)
    LED : 저항(220~330옴) 경유 -> 물리 13번 (GPIO27),  다른쪽 -> GND (물리 6번)

사용법
    python3 walkcam_button.py
    python3 walkcam_button.py --led-pin 26 --button-pin 5
    python3 walkcam_button.py --duration 1800     # 세션당 최대 30분
    python3 walkcam_button.py --keyboard          # 버튼 없이 Enter로 토글
"""

from __future__ import annotations

import argparse
import logging
import signal
import sys
import threading
import time
from enum import Enum

from gpiozero import LED, Button

from walkcam_v3 import (
    CamConfig,
    CompositeReporter,
    HealthSample,
    HealthState,
    LogReporter,
    StatusReporter,
    WalkCam,
    setup_console_logging,
)

# ─────────────────────────────────────────────────────────
# 런처 설정
# ─────────────────────────────────────────────────────────

BUTTON_PIN = 17          # BCM / 물리 11번
LED_PIN = 27             # BCM / 물리 13번

# 기계식 스위치 접점 떨림 무시 구간(초). gpiozero가 처리합니다.
BOUNCE_TIME = 0.15

# 디바운스를 통과했더라도 이 간격 안의 재입력은 무시합니다.
# 녹화 시작/종료는 비용이 큰 동작이라, 한 번의 의도가 두 번 실행되면
# 시작 직후 곧바로 종료되는 빈 세션이 생깁니다.
MIN_PRESS_INTERVAL = 1.0

# (on_time, off_time). None이면 점등 고정.
LED_PATTERNS = {
    "starting": (0.5, 0.5),
    "recording": None,
    "stalled": (0.1, 0.1),
}


# ─────────────────────────────────────────────────────────
# LED 리포터
# ─────────────────────────────────────────────────────────


class LedReporter(StatusReporter):
    """녹화 상태를 LED로 알립니다.

    LED 객체의 소유자는 런처입니다. 이 리포터는 패턴만 바꿉니다.
    따라서 close()는 아무것도 하지 않습니다. 세션이 끝날 때마다
    CompositeReporter가 close()를 부르지만, LED는 프로그램 수명 동안
    유지되어야 하므로 여기서 닫으면 다음 세션에서 쓸 수 없게 됩니다.
    """

    def __init__(self, led: LED):
        self.led = led

    def _apply(self, key: str) -> None:
        pattern = LED_PATTERNS.get(key)
        if pattern is None:
            self.led.on()
        else:
            # blink()는 논블로킹입니다. on()/off()가 자동으로 취소합니다.
            self.led.blink(on_time=pattern[0], off_time=pattern[1])

    def indicate_starting(self) -> None:
        """버튼이 눌린 직후. 아직 파일이 자라는지는 알 수 없는 구간."""
        self._apply("starting")

    def on_state_change(self, sample: HealthSample) -> None:
        if sample.state is HealthState.STALLED:
            self._apply("stalled")
        elif sample.state is HealthState.RECORDING:
            self._apply("recording")
        else:
            self._apply("starting")

    def on_finish(self, final_state: HealthState) -> None:
        self.led.off()

    def close(self) -> None:
        pass


# ─────────────────────────────────────────────────────────
# 토글 상태 기계
# ─────────────────────────────────────────────────────────


class SessionState(Enum):
    IDLE = "대기"
    RECORDING = "녹화 중"
    STOPPING = "종료 중"


class RecordingToggle:
    """버튼 입력 한 번을 세션 시작 또는 종료로 해석합니다.

    종료는 요청만 하고 기다리지 않습니다. WalkCam.stop()은 stop_timeout까지
    걸릴 수 있는데, 그 시간 동안 버튼 콜백 스레드를 붙잡고 있으면 이후 입력이
    전부 밀립니다. 실제 정리는 워커 스레드가 끝내고, 그 사이의 입력은
    STOPPING 상태로 걸러냅니다.
    """

    def __init__(
        self,
        led_reporter: LedReporter,
        log: logging.Logger,
        config: CamConfig,
        duration: float | None = None,
    ):
        self.led_reporter = led_reporter
        self.log = log
        self.config = config
        self.duration = duration

        self._lock = threading.RLock()
        self._state = SessionState.IDLE
        self._cam: WalkCam | None = None
        self._thread: threading.Thread | None = None
        self._last_press = 0.0
        self._session_count = 0

    @property
    def state(self) -> SessionState:
        with self._lock:
            return self._state

    # ── 외부 진입점 ──────────────────────────────────────

    def on_press(self) -> None:
        """버튼 콜백. gpiozero의 백그라운드 스레드에서 호출됩니다.

        gpiozero는 콜백에서 발생한 예외를 조용히 삼킬 수 있습니다.
        여기서 잡지 않으면 원인 모를 무반응 상태가 되므로 반드시 감쌉니다.
        """
        try:
            self._on_press()
        except Exception:
            self.log.exception("버튼 처리 중 오류")

    def _on_press(self) -> None:
        now = time.monotonic()

        with self._lock:
            if now - self._last_press < MIN_PRESS_INTERVAL:
                self.log.debug("연속 입력 무시 (%.2f초 간격)", now - self._last_press)
                return
            self._last_press = now

            if self._state is SessionState.IDLE:
                self._start()
            elif self._state is SessionState.RECORDING:
                self._request_stop()
            else:
                self.log.info("이전 세션을 정리하는 중입니다. 잠시 후 다시 눌러주세요.")

    def shutdown(self) -> None:
        """프로그램 종료 시 호출. 진행 중인 세션을 정리하고 기다립니다."""
        with self._lock:
            thread = self._thread
            if self._state is SessionState.RECORDING:
                self._request_stop()

        if thread is not None and thread.is_alive():
            self.log.info("녹화 정리를 기다립니다...")
            thread.join(timeout=self.config.stop_timeout + 10.0)
            if thread.is_alive():
                self.log.error(
                    "녹화 스레드가 종료되지 않았습니다. "
                    "마지막 세그먼트가 손상될 수 있습니다."
                )

    # ── 내부 (호출 시 _lock 보유 필요) ───────────────────

    def _start(self) -> None:
        self._session_count += 1
        session_no = self._session_count

        # 세션마다 새 인스턴스를 만듭니다. v3의 WalkCam은 1회용이며,
        # 재사용하면 RuntimeError로 명확히 실패합니다.
        cam = WalkCam(
            duration=self.duration,
            config=self.config,
            reporter=CompositeReporter(
                LogReporter(self.log),
                self.led_reporter,
            ),
        )

        thread = threading.Thread(
            target=self._worker,
            args=(cam, session_no),
            name=f"walkcam-session-{session_no}",
            daemon=False,
        )

        try:
            self._cam = cam
            self._state = SessionState.RECORDING
            # 카메라 초기화에 수 초가 걸립니다. 버튼을 누른 즉시 느린 점멸로
            # "입력이 접수됐다"는 사실부터 눈으로 확인할 수 있게 합니다.
            self.led_reporter.indicate_starting()
            self._thread = thread
            thread.start()
        except Exception:
            # 스레드 생성 실패 등으로 여기까지 오면 상태를 되돌립니다.
            # 그러지 않으면 LED가 켜진 채 RECORDING으로 고착됩니다.
            self._state = SessionState.IDLE
            self._cam = None
            self._thread = None
            self.led_reporter.led.off()
            raise

        self.log.info("=" * 52)
        self.log.info("세션 #%d 시작 요청", session_no)

    def _request_stop(self) -> None:
        self._state = SessionState.STOPPING
        self.log.info("세션 #%d 종료 요청", self._session_count)
        if self._cam is not None:
            self._cam.request_stop()

    # ── 워커 ─────────────────────────────────────────────

    def _worker(self, cam: WalkCam, session_no: int) -> None:
        """run()이 촬영부터 리포트 출력, 메타데이터 저장까지 전부 처리합니다.

        install_signal_handlers를 넘기지 않습니다(기본 False).
        signal.signal()은 메인 스레드에서만 호출할 수 있고, 시그널 처리는
        런처의 메인 스레드가 담당합니다.
        """
        try:
            exit_code = cam.run()
            if exit_code == 0:
                self.log.info("세션 #%d 정상 종료", session_no)
            else:
                self.log.warning("세션 #%d 이상 종료 (exit=%d)", session_no, exit_code)
        except Exception:
            self.log.exception("세션 #%d 실행 중 오류", session_no)
        finally:
            # LED 소등을 여기서 한 번 더 보장합니다.
            # 예외로 reporter.on_finish()가 호출되지 못했더라도
            # LED가 켜진 채 남아 "녹화 중"으로 오해되는 일이 없어야 합니다.
            try:
                self.led_reporter.led.off()
            except Exception:
                pass

            with self._lock:
                self._state = SessionState.IDLE
                self._cam = None
                self._thread = None

            self.log.info("대기 상태 — 버튼을 누르면 새 세션이 시작됩니다.")
            self.log.info("=" * 52)


# ─────────────────────────────────────────────────────────
# 진입점
# ─────────────────────────────────────────────────────────


def run_keyboard_mode(
    toggle: RecordingToggle,
    log: logging.Logger,
    shutdown: threading.Event,
) -> None:
    """버튼 없이 Enter로 토글합니다.

    카메라 문제와 버튼 배선 문제를 분리해서 확인할 때 씁니다.
    """
    log.info("키보드 모드 — Enter로 시작/종료, Ctrl+C로 프로그램 종료")
    while not shutdown.is_set():
        try:
            input()
        except EOFError:
            break
        toggle.on_press()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="버튼 토글로 산책 영상 녹화를 시작/종료합니다."
    )
    parser.add_argument("--button-pin", type=int, default=BUTTON_PIN,
                        help=f"버튼 GPIO 번호(BCM). 기본 {BUTTON_PIN}")
    parser.add_argument("--led-pin", type=int, default=LED_PIN,
                        help=f"LED GPIO 번호(BCM). 기본 {LED_PIN}")
    parser.add_argument("--duration", type=float, default=None,
                        help="세션당 최대 녹화 시간(초). 생략하면 버튼으로만 종료")
    parser.add_argument("--keyboard", action="store_true",
                        help="버튼 대신 Enter로 토글(배선 문제 격리용)")
    parser.add_argument("--no-probe-camera", action="store_true",
                        help="시작 전 카메라 감지 확인을 생략")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    log = setup_console_logging(args.verbose)
    config = CamConfig()

    # 촬영 환경은 버튼을 눌러본 뒤가 아니라 시작 전에 확인합니다.
    try:
        WalkCam.check_environment(config, probe_camera=not args.no_probe_camera)
    except RuntimeError as e:
        log.error("%s", e)
        return 1

    led: LED | None = None
    button: Button | None = None
    toggle: RecordingToggle | None = None
    shutdown = threading.Event()

    try:
        led = LED(args.led_pin)
        led.off()

        toggle = RecordingToggle(
            LedReporter(led), log, config, duration=args.duration
        )

        # SIGINT는 기본 동작(KeyboardInterrupt)을 그대로 둡니다.
        # 커스텀 핸들러를 걸면 --keyboard 모드의 input()이 EINTR 처리에서
        # 예측하기 어렵게 동작합니다. SIGTERM만 이벤트로 연결합니다.
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

            log.info("준비 완료  (버튼 GPIO%d / LED GPIO%d)",
                     args.button_pin, args.led_pin)
            log.info("버튼을 누르면 녹화가 시작됩니다. 프로그램 종료는 Ctrl+C")
            shutdown.wait()

        log.info("종료 신호 수신")
        return 0

    except KeyboardInterrupt:
        log.info("중단 요청 수신")
        return 0

    finally:
        # toggle이 만들어지기 전에 예외가 났을 수도 있으므로 None을 확인합니다.
        if toggle is not None:
            toggle.shutdown()
        if button is not None:
            button.close()
        if led is not None:
            led.off()
            led.close()


if __name__ == "__main__":
    sys.exit(main())
