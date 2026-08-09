#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
oled_status.py — 녹화 상태를 OLED에 보여주는 표시 계층

SSD1309 드라이버(ssd1309.py) 위에서 동작하는 백그라운드 렌더 스레드입니다.
walkcam 쪽 코드는 전혀 모릅니다. set_state() 같은 공개 메서드만 노출하고,
녹화 이벤트를 이 메서드로 연결하는 일은 런처(walkcam_oled.py)가 합니다.

상태 화면
    WAITING    "촬영 대기"        버튼 입력을 기다리는 중
    STARTING   "카메라 준비 중"   버튼은 눌렸지만 파일이 아직 안 자람
    RECORDING  "● REC mm:ss"     정상 녹화 — 경과 시간이 1초 단위로 갱신
    STALLED    "! 데이터 정체"    프로세스는 떠 있는데 파일이 안 자람
    STOPPING   "저장 중..."       종료 요청 후 정리 구간

경과 시간은 이 스레드가 직접 계산합니다. walkcam_v3의 heartbeat는
간격이 길어서(기본 수십 초) 초 단위 시계로 쓸 수 없기 때문입니다.
session_started()가 호출된 시각을 기준으로 매 초 다시 그립니다.

향후 확장(버튼으로 창 전환)
    화면 하나가 Screen 객체 하나입니다. 지금은 StatusScreen 하나만
    등록돼 있고, 나중에 통계 화면·설정 화면을 추가하면
    display.next_screen()을 버튼 콜백에 연결하는 것으로 끝납니다.

한글 폰트
    PIL 기본 폰트는 한글을 렌더링하지 못합니다. 나눔고딕이 있으면 한글로,
    없으면 영문 문구로 자동 전환합니다.
        sudo apt install fonts-nanum

단독 테스트 (배선 확인용 — 카메라 없이 상태를 순환 재생)
    python3 oled_status.py
"""

from __future__ import annotations

import threading
import time
from enum import Enum
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from ssd1309 import HEIGHT, WIDTH, SSD1309_SPI

# ─────────────────────────────────────────────────────────
# 폰트
# ─────────────────────────────────────────────────────────

_FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf",
    "/usr/share/fonts/truetype/nanum/NanumGothic.ttf",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
]


def _load_fonts():
    """(작은 폰트, 큰 폰트, 한글 지원 여부)를 돌려줍니다."""
    for path in _FONT_CANDIDATES:
        if Path(path).exists():
            return (
                ImageFont.truetype(path, 12),
                ImageFont.truetype(path, 16),
                True,
            )
    # 한글 폰트가 없으면 기본 비트맵 폰트 + 영문 문구로 동작합니다.
    f = ImageFont.load_default()
    return f, f, False


# ─────────────────────────────────────────────────────────
# 상태 정의
# ─────────────────────────────────────────────────────────


class ScreenState(Enum):
    IDLE = "idle"                # 도킹 대기 — 하트 표시
    WAITING = "waiting"
    STARTING = "starting"
    RECORDING = "recording"
    STALLED = "stalled"
    STOPPING = "stopping"
    TRANSFERRING = "transferring"  # 도킹 후 영상 전송 중


# 상태별 문구. (한글, 영문 폴백)
_LABELS = {
    ScreenState.IDLE:         ("",             ""),
    ScreenState.WAITING:      ("촬영 대기",     "READY"),
    ScreenState.STARTING:     ("카메라 준비 중", "STARTING"),
    ScreenState.RECORDING:    ("녹화 중",       "RECORDING"),
    ScreenState.STALLED:      ("데이터 정체!",   "STALLED!"),
    ScreenState.STOPPING:     ("저장 중",       "SAVING"),
    ScreenState.TRANSFERRING: ("전송 중",       "SENDING"),
}


def _draw_heart(draw, cx: int, cy: int, w: int, fill=1) -> None:
    """(cx, cy)를 중심으로 폭 w의 하트를 그립니다.

    두 개의 원(윗부분 볼록한 곳)과 삼각형(아래 뾰족한 끝)의 조합입니다.
    128x32 패널에서는 w=20~26 정도가 적당합니다.
    """
    h = int(w * 0.9)
    r = w // 4                      # 볼록한 부분 원의 반지름
    top = cy - h // 2
    # 왼쪽/오른쪽 볼록이
    draw.ellipse((cx - 2 * r, top, cx, top + 2 * r), fill=fill)
    draw.ellipse((cx, top, cx + 2 * r, top + 2 * r), fill=fill)
    # 아래 뾰족이
    draw.polygon(
        [(cx - 2 * r, top + r), (cx + 2 * r, top + r), (cx, cy + h // 2)],
        fill=fill,
    )


def _fmt_elapsed(sec: float) -> str:
    m, s = divmod(int(sec), 60)
    if m >= 60:
        h, m = divmod(m, 60)
        return f"{h}:{m:02d}:{s:02d}"
    return f"{m:02d}:{s:02d}"


# ─────────────────────────────────────────────────────────
# 화면 (향후 버튼으로 전환할 창의 단위)
# ─────────────────────────────────────────────────────────


class Screen:
    """한 장의 화면. render()가 프레임을 그립니다.

    반환값은 '이 프레임을 대표하는 키'입니다. 키가 직전과 같으면
    내용이 안 바뀐 것이므로 SPI 전송을 생략합니다. Pi Zero W에서
    녹화 인코딩과 CPU를 나눠 써야 하므로, 초가 바뀔 때만 그립니다.
    """

    def render(self, draw: ImageDraw.ImageDraw, ctx: "DisplayContext"):
        raise NotImplementedError


class DisplayContext:
    """렌더링에 필요한 공유 상태. 스레드 잠금은 디스플레이가 관리합니다."""

    def __init__(self, font_small, font_big, korean: bool):
        self.font_small = font_small
        self.font_big = font_big
        self.korean = korean

        self.state = ScreenState.WAITING
        self.session_started_at: float | None = None
        self.segment_count = 0
        self.free_mb: float | None = None

    def label(self, state: ScreenState) -> str:
        ko, en = _LABELS[state]
        return ko if self.korean else en

    def elapsed(self) -> float:
        if self.session_started_at is None:
            return 0.0
        return time.monotonic() - self.session_started_at


class StatusScreen(Screen):
    """기본 화면: 상태 문구 + 경과 시간."""

    def render(self, draw, ctx):
        state = ctx.state
        label = ctx.label(state)
        blink = int(time.monotonic() * 2) % 2 == 0  # 0.5초 주기 점멸

        if state is ScreenState.IDLE:
            # 도킹 대기: 화면 가운데 하트가 천천히 박동합니다.
            beat = int(time.monotonic() / 0.75) % 2 == 0
            _draw_heart(draw, WIDTH // 2, HEIGHT // 2, 24 if beat else 20)
            key = ("idle", beat)

        elif state is ScreenState.TRANSFERRING:
            # 도킹 후 전송 중: 문구 + 진행 점 + 흐르는 화살표
            dots = "." * (int(time.monotonic() * 2) % 4)
            draw.text((WIDTH // 2, 10), label + dots,
                      font=ctx.font_big, fill=1, anchor="mm")
            # 아래쪽에 오른쪽으로 흘러가는 작은 화살촉 3개
            phase = int(time.monotonic() * 4) % 4
            for i in range(3):
                x = 40 + i * 20 + phase * 5
                draw.polygon([(x, 22), (x, 30), (x + 6, 26)], fill=1)
            key = ("xfer", dots, phase)

        elif state is ScreenState.WAITING:
            # 가운데 크게 "촬영 대기", 아래에 안내 한 줄
            draw.text((WIDTH // 2, 8), label,
                      font=ctx.font_big, fill=1, anchor="mm")
            hint = "버튼: 녹화 시작" if ctx.korean else "PRESS BTN TO REC"
            draw.text((WIDTH // 2, 24), hint,
                      font=ctx.font_small, fill=1, anchor="mm")
            key = ("wait",)

        elif state is ScreenState.STARTING:
            dots = "." * (int(time.monotonic() * 2) % 4)
            draw.text((2, 2), label + dots, font=ctx.font_small, fill=1)
            draw.text((2, 17), _fmt_elapsed(ctx.elapsed()),
                      font=ctx.font_small, fill=1)
            key = ("start", dots, int(ctx.elapsed()))

        elif state is ScreenState.RECORDING:
            # ● REC 점멸 + 경과 시간 크게
            if blink:
                draw.ellipse((2, 4, 10, 12), fill=1)
            draw.text((14, 2), label, font=ctx.font_small, fill=1)
            draw.text((2, 15), _fmt_elapsed(ctx.elapsed()),
                      font=ctx.font_big, fill=1)
            if ctx.segment_count:
                seg = f"{ctx.segment_count}seg"
                draw.text((WIDTH - 2, 24), seg,
                          font=ctx.font_small, fill=1, anchor="rm")
            key = ("rec", blink, int(ctx.elapsed()), ctx.segment_count)

        elif state is ScreenState.STALLED:
            # 반전 점멸로 눈에 띄게. 빠른 LED 점멸과 같은 의미입니다.
            if blink:
                draw.rectangle((0, 0, WIDTH - 1, HEIGHT - 1), fill=1)
                fill = 0
            else:
                fill = 1
            draw.text((WIDTH // 2, 8), label,
                      font=ctx.font_big, fill=fill, anchor="mm")
            draw.text((WIDTH // 2, 24), _fmt_elapsed(ctx.elapsed()),
                      font=ctx.font_small, fill=fill, anchor="mm")
            key = ("stall", blink, int(ctx.elapsed()))

        else:  # STOPPING
            dots = "." * (int(time.monotonic() * 2) % 4)
            draw.text((WIDTH // 2, 16), label + dots,
                      font=ctx.font_big, fill=1, anchor="mm")
            key = ("stop", dots)

        return key


# ─────────────────────────────────────────────────────────
# 디스플레이 본체
# ─────────────────────────────────────────────────────────


class OledStatusDisplay:
    """OLED 갱신 전담 스레드.

    소유권: 런처가 만들고 런처가 close()합니다. 세션(WalkCam)의 수명과
    무관하게 프로그램이 도는 내내 켜져 있어야 하기 때문입니다.
    LED와 마찬가지로, 세션이 끝날 때 CompositeReporter가 close()를
    불러도 화면이 꺼지지 않도록 리포터 쪽 close()는 비워 둡니다.
    """

    TICK = 0.1  # 렌더 판단 주기. 실제 SPI 전송은 내용이 바뀔 때만.

    def __init__(self, rotate: bool = True):
        """rotate=True면 패널 장착 방향에 맞춰 화면을 180도 뒤집어 출력."""
        font_small, font_big, korean = _load_fonts()
        self.ctx = DisplayContext(font_small, font_big, korean)
        self.rotate = rotate

        self._oled = SSD1309_SPI()
        self._oled.init()

        self._screens: list[Screen] = [StatusScreen()]
        self._screen_idx = 0

        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._last_key = None
        self._thread = threading.Thread(
            target=self._loop, name="oled-display", daemon=True
        )

    # ── 수명 관리 ────────────────────────────────────────

    def start(self) -> None:
        self._thread.start()

    def close(self) -> None:
        self._stop.set()
        self._thread.join(timeout=2.0)
        self._oled.close()

    # ── 상태 변경 (스레드 안전 — 어느 스레드에서 불러도 됨) ──

    def set_state(self, state: ScreenState) -> None:
        with self._lock:
            self.ctx.state = state

    def session_starting(self) -> None:
        """버튼이 눌린 직후. 경과 시계도 여기서 0으로 시작합니다."""
        with self._lock:
            self.ctx.state = ScreenState.STARTING
            self.ctx.session_started_at = time.monotonic()
            self.ctx.segment_count = 0

    def session_finished(self) -> None:
        with self._lock:
            self.ctx.state = ScreenState.WAITING
            self.ctx.session_started_at = None
            self.ctx.segment_count = 0

    def update_stats(self, segment_count: int, free_mb: float) -> None:
        with self._lock:
            self.ctx.segment_count = segment_count
            self.ctx.free_mb = free_mb

    # ── 향후 확장: 버튼으로 창 전환 ──────────────────────

    def add_screen(self, screen: Screen) -> None:
        self._screens.append(screen)

    def next_screen(self) -> None:
        """다른(짧게/두 번째) 버튼 콜백에 연결하면 창이 순환됩니다."""
        with self._lock:
            self._screen_idx = (self._screen_idx + 1) % len(self._screens)
            self._last_key = None  # 강제 다시 그리기

    # ── 렌더 루프 ────────────────────────────────────────

    def _loop(self) -> None:
        while not self._stop.is_set():
            try:
                with self._lock:
                    screen = self._screens[self._screen_idx]
                    img = Image.new("1", (WIDTH, HEIGHT), 0)
                    draw = ImageDraw.Draw(img)
                    key = (self._screen_idx, screen.render(draw, self.ctx))

                if key != self._last_key:
                    # 패널 장착 방향 보정: 최종 프레임만 뒤집으므로
                    # 화면 레이아웃 좌표는 원래 방향 기준 그대로입니다.
                    if self.rotate:
                        img = img.transpose(Image.ROTATE_180)
                    self._oled.image(img)
                    self._last_key = key
            except Exception:
                # 화면 갱신 실패가 녹화를 죽여서는 안 됩니다.
                # 잠시 쉬었다가 계속 시도합니다.
                time.sleep(1.0)

            self._stop.wait(self.TICK)


# ─────────────────────────────────────────────────────────
# 단독 테스트: 카메라 없이 상태를 순환 재생
# ─────────────────────────────────────────────────────────

if __name__ == "__main__":
    display = OledStatusDisplay()
    display.start()
    print("한글 폰트:", "사용" if display.ctx.korean else
          "없음 (영문 표시) — sudo apt install fonts-nanum")
    try:
        while True:
            print("[IDLE] 도킹 대기 — 하트 박동")
            display.set_state(ScreenState.IDLE)
            time.sleep(5)

            print("[TRANSFERRING] 전송 중")
            display.set_state(ScreenState.TRANSFERRING)
            time.sleep(5)

            print("[WAITING] 촬영 대기")
            display.session_finished()
            time.sleep(4)

            print("[STARTING] 카메라 준비 중")
            display.session_starting()
            time.sleep(4)

            print("[RECORDING] 녹화 중 + 경과 시간")
            display.set_state(ScreenState.RECORDING)
            display.update_stats(segment_count=3, free_mb=1024.0)
            time.sleep(10)

            print("[STALLED] 데이터 정체")
            display.set_state(ScreenState.STALLED)
            time.sleep(4)

            print("[STOPPING] 저장 중")
            display.set_state(ScreenState.STOPPING)
            time.sleep(3)
    except KeyboardInterrupt:
        pass
    finally:
        display.close()
        print("\n종료합니다.")
