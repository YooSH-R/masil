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

import math
import random
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
    """(작은, 큰, 제목10, 시간20, 한글 지원 여부)를 돌려줍니다.

    제목/시간 폰트는 축하 화면용 — 크기 비율 1:2.
    """
    for path in _FONT_CANDIDATES:
        if Path(path).exists():
            return (
                ImageFont.truetype(path, 12),
                ImageFont.truetype(path, 16),
                ImageFont.truetype(path, 10),
                ImageFont.truetype(path, 18),
                True,
            )
    # 한글 폰트가 없으면 기본 비트맵 폰트 + 영문 문구로 동작합니다.
    f = ImageFont.load_default()
    return f, f, f, f, False


# 러너 1완주 = 1세그먼트에 해당하는 시간(초). walkcam_v3의 세그먼트
# 길이(5분)와 맞춰 둔 시각적 근사치입니다.
SEGMENT_SECONDS = 300


def _draw_runner(draw, x: int, y: int, frame: int, fill=1) -> None:
    """(x, y)를 좌상단으로 하는 폭 ~9px, 높이 ~11px의 달리는 사람.

    frame 0/1 두 자세를 번갈아 그리면 달리는 애니메이션이 됩니다.
    """
    # 머리
    draw.ellipse((x + 3, y, x + 6, y + 3), fill=fill)
    # 몸통 (앞으로 기운 자세)
    draw.line((x + 4, y + 3, x + 3, y + 7), fill=fill)
    if frame == 0:
        # 팔: 앞뒤로 크게, 다리: 앞뒤로 벌림
        draw.line((x + 4, y + 4, x + 8, y + 3), fill=fill)
        draw.line((x + 4, y + 5, x + 1, y + 6), fill=fill)
        draw.line((x + 3, y + 7, x + 7, y + 10), fill=fill)
        draw.line((x + 3, y + 7, x, y + 9), fill=fill)
    else:
        # 반대 위상: 팔 교차, 다리 모임
        draw.line((x + 4, y + 4, x + 1, y + 3), fill=fill)
        draw.line((x + 4, y + 5, x + 7, y + 6), fill=fill)
        draw.line((x + 3, y + 7, x + 5, y + 11), fill=fill)
        draw.line((x + 3, y + 7, x + 1, y + 11), fill=fill)





def _draw_manse(draw, x: int, y: int, up: bool, fill=1) -> None:
    """(x, y) 좌상단 기준 폭 ~9px, 높이 ~11px의 만세 사람.

    up=True면 두 팔을 V자로 번쩍, False면 팔을 내린 자세.
    """
    draw.ellipse((x + 3, y, x + 6, y + 3), fill=fill)          # 머리
    draw.line((x + 4, y + 3, x + 4, y + 7), fill=fill)          # 몸통
    if up:                                                       # 만세!
        draw.line((x + 4, y + 4, x + 1, y), fill=fill)
        draw.line((x + 4, y + 4, x + 8, y), fill=fill)
    else:                                                        # 차렷
        draw.line((x + 4, y + 4, x + 1, y + 7), fill=fill)
        draw.line((x + 4, y + 4, x + 8, y + 7), fill=fill)
    draw.line((x + 4, y + 7, x + 1, y + 11), fill=fill)          # 다리
    draw.line((x + 4, y + 7, x + 7, y + 11), fill=fill)


def _draw_popper(draw, cx: int, cy: int, p: float, flip: bool, fill=1) -> None:
    """🎉 파티 포퍼: 기울어진 원뿔 + 퍼져나가는 콘페티.

    p(0~1)가 커질수록 콘페티가 원뿔 입구에서 멀리 퍼집니다.
    flip=True면 좌우 반전(오른쪽 배치용) — 원뿔이 안쪽을 향합니다.
    """
    s = -1 if flip else 1
    # 원뿔 (이모지처럼 대각선으로 기울임, 입구가 위-안쪽)
    draw.polygon([(cx - s * 4, cy + 4), (cx + s * 1, cy - 1),
                  (cx + s * 3, cy + 1)], fill=fill)
    # 콘페티: 입구에서 부채꼴로 3갈래 + 점 2개, 반경은 p에 비례
    r = 2 + p * 6
    for ang in (25, 55, 85):
        a = math.radians(ang)
        px = cx + s * int(math.cos(a) * r) + s * 1
        py = cy - 1 - int(math.sin(a) * r)
        if 0 <= px < WIDTH and 0 <= py < HEIGHT:
            draw.point((px, py), fill=fill)
            draw.point((px - s, py), fill=fill)          # 종이조각 느낌 2px
    # 흩날리는 점 (조금 바깥)
    for ang in (40, 70):
        a = math.radians(ang)
        px = cx + s * int(math.cos(a) * (r + 2)) + s * 1
        py = cy - 1 - int(math.sin(a) * (r + 2))
        if 0 <= px < WIDTH and 0 <= py < HEIGHT:
            draw.point((px, py), fill=fill)


# ─────────────────────────────────────────────────────────
# 하트 분출(버스트) — 대기 화면 이벤트 (heart.py에서 이식)
# 키 입력 한 번에 중앙 하트에서 6방향으로 동시 발사됩니다.
# ─────────────────────────────────────────────────────────

_SMALL_HEART_ART = [
    ["X.X",
     "XXX",
     ".X."],
    [".X.X.",
     "XXXXX",
     "XXXXX",
     ".XXX.",
     "..X.."],
    [".XX.XX.",
     "XXXXXXX",
     "XXXXXXX",
     "XXXXXXX",
     ".XXXXX.",
     "..XXX..",
     "...X..."],
]


def _art_to_pixels(art):
    h, w = len(art), len(art[0])
    return [(x - w // 2, y - h // 2)
            for y, row in enumerate(art)
            for x, ch in enumerate(row) if ch == "X"]


_SMALL_PIXELS = [_art_to_pixels(a) for a in _SMALL_HEART_ART]

# 좌 / 우 / 좌상 / 우상 / 좌하 / 우하 — 6방향 동시 발사
_BURST_DIRECTIONS_DEG = [180, 0, 135, 45, 225, 315]

_GROW_STEP = 0.35        # 이 시간(초)마다 하트가 한 단계 커짐
_WOBBLE_AMP = 1.6        # 위아래 흔들림 진폭(픽셀)
_BURST_SPEED = (16.0, 24.0)
_BURST_GRAVITY = 22.0    # px/s^2 — 포물선 낙하


class _FlyingHeart:
    """중앙 하트에서 튀어나와 포물선을 그리는 작은 하트."""

    def __init__(self, cx: float, cy: float, angle_deg: float):
        rad = math.radians(angle_deg)
        speed = random.uniform(*_BURST_SPEED)
        # 중앙 하트 가장자리에서 출발하는 느낌 (가로 12 / 세로 9 오프셋)
        self.x = cx + math.cos(rad) * 12
        self.y = cy - math.sin(rad) * 9
        self.vx = math.cos(rad) * speed
        self.vy = -math.sin(rad) * speed      # 화면 좌표(y 아래 = +)
        self.age = 0.0
        self._wp = random.uniform(0, 2 * math.pi)
        self._ws = random.uniform(6.0, 9.0)

    def update(self, dt: float) -> None:
        self.age += dt
        self.vy += _BURST_GRAVITY * dt
        self.x += self.vx * dt
        self.y += self.vy * dt

    @property
    def alive(self) -> bool:
        return -8 < self.x < WIDTH + 8 and self.y < HEIGHT + 8

    def size_index(self) -> int:
        return min(2, int(self.age / _GROW_STEP))

    def draw(self, draw) -> None:
        wob = _WOBBLE_AMP * math.sin(self._wp + self.age * self._ws)
        cx, cy = int(self.x), int(self.y + wob)
        for dx, dy in _SMALL_PIXELS[self.size_index()]:
            px, py = cx + dx, cy + dy
            if 0 <= px < WIDTH and 0 <= py < HEIGHT:
                draw.point((px, py), fill=1)


class ScreenState(Enum):
    IDLE = "idle"                # 도킹 대기 — 하트 표시
    WAITING = "waiting"
    STARTING = "starting"
    RECORDING = "recording"
    STALLED = "stalled"
    STOPPING = "stopping"
    CELEBRATE = "celebrate"        # 산책 완료 축하 (저장 후 자동 전환)
    BEGGING = "begging"            # 산책 조르기 (2번 키 토글)
    CLOCK = "clock"                # 현재 시각 표시 (3번 키 토글)
    GREETING = "greeting"          # 주인 마중 (4번 키 토글)
    TRANSFERRING = "transferring"  # 도킹 후 영상 전송 중


# 상태별 문구. (한글, 영문 폴백)
_LABELS = {
    ScreenState.IDLE:         ("",             ""),
    ScreenState.WAITING:      ("촬영 대기",     "READY"),
    ScreenState.STARTING:     ("카메라 준비 중", "STARTING"),
    ScreenState.RECORDING:    ("녹화 중",       "RECORDING"),
    ScreenState.STALLED:      ("데이터 정체!",   "STALLED!"),
    ScreenState.STOPPING:     ("저장 중",       "SAVING"),
    ScreenState.CELEBRATE:    ("산책 완료",     "DONE!"),
    ScreenState.BEGGING:      ("",             ""),
    ScreenState.CLOCK:        ("",             ""),
    ScreenState.GREETING:     ("",             ""),
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

    def __init__(self, font_small, font_big, font_title, font_time,
                 korean: bool):
        self.font_small = font_small
        self.font_big = font_big
        self.font_title = font_title      # 축하 화면 제목 (비율 1)
        self.font_time = font_time        # 축하 화면 시간 (비율 2)
        self.korean = korean

        self.state = ScreenState.WAITING
        self.session_started_at: float | None = None
        self.segment_count = 0
        self.free_mb: float | None = None

        # 하트 버스트 상태 (IDLE 화면 전용)
        self.flying_hearts: list[_FlyingHeart] = []
        self.fly_last_t: float | None = None

        # 산책 완료 축하 화면 상태
        self.celebrate_started_at: float | None = None
        self.celebrate_duration: float = 0.0      # 표시할 산책 시간(초)

        # 산책 조르기 화면 상태
        self.beg_last_walk: float | None = None   # 마지막 산책 epoch(초)

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
            # 대기: 가운데 하트 박동 + (버스트 시) 6방향 하트 분출
            beat = int(time.monotonic() / 0.75) % 2 == 0
            _draw_heart(draw, WIDTH // 2, HEIGHT // 2 + 4, 24 if beat else 20)

            if ctx.flying_hearts:
                now = time.monotonic()
                dt = min(now - (ctx.fly_last_t or now), 0.1)
                ctx.fly_last_t = now
                for fh in ctx.flying_hearts:
                    fh.update(dt)
                ctx.flying_hearts = [fh for fh in ctx.flying_hearts if fh.alive]
                for fh in ctx.flying_hearts:
                    fh.draw(draw)
                key = ("idle", beat, tuple(
                    (int(fh.x), int(fh.y), fh.size_index())
                    for fh in ctx.flying_hearts))
            else:
                ctx.fly_last_t = None
                key = ("idle", beat)

        elif state is ScreenState.GREETING:
            # 주인 마중: 배(심장 자리)에서 빠르고 크게 쿵쿵 뛰는 하트 +
            # 박동마다 양옆에서 작은 하트가 퐁 떠올라 사라짐 + 반김 문구.
            t = time.monotonic()

            # 좌: 쿵쿵 하트(배 = 심장) / 우: 반김 문구 — 32px 세로에
            # 수직 적층이 안 되므로 좌우 배치. 가림 영역(상단 8px) 회피.
            # 쿵쿵 하트: 대기(0.75초)보다 3배 빠른 0.25초 박동
            beat = int(t / 0.25) % 2 == 0
            _draw_heart(draw, 28, 20, 24 if beat else 18)

            # 반김 문구 — 2초마다 교차, 부드럽게 깜빡(0.75초 표시/0.25초 숨김)
            msgs = (("어서와!!", "보고싶었어!")
                    if ctx.korean else ("WELCOME!!", "MISSED YOU!"))
            mi = int(t / 2) % len(msgs)
            txt_on = (t % 1.0) < 0.75
            if txt_on:
                draw.text((90, 16), msgs[mi],
                          font=ctx.font_small, fill=1, anchor="mm")

            # 퐁퐁 작은 하트: 한 박동(0.5초)마다 하트 좌우에서 떠올라 소멸
            p = (t % 0.5) / 0.5
            if p < 0.9:
                stage = 0 if p < 0.45 else 1
                for sx, rise in ((10, 10), (47, 8)):
                    cx, cy = sx, int(25 - p * rise)
                    for dx, dy in _SMALL_PIXELS[stage]:
                        px, py = cx + dx, cy + dy
                        if 0 <= px < WIDTH and 8 <= py < HEIGHT:
                            draw.point((px, py), fill=1)

            key = ("greet", mi, txt_on, beat, int(p * 10))

        elif state is ScreenState.CLOCK:
            # 시계: 시스템 시각(HH:MM:SS)만 중앙에 크게.
            # 가림 영역(상단 8px)을 피해 가용 영역 세로 중앙에 배치.
            now_txt = time.strftime("%H:%M:%S")
            draw.text((WIDTH // 2, 20), now_txt,
                      font=ctx.font_time, fill=1, anchor="mm")
            key = ("clock", now_txt)

        elif state is ScreenState.BEGGING:
            # 산책 조르기: 말풍선(순환) + 마지막 산책 카운트 +
            # 문 앞을 서성이다 도착하면 콩콩 두드리는 사람
            t = time.monotonic()

            # 말풍선 — 2초마다 문구 순환
            msgs = (("산책 가자!", "나가자~", "심심해...")
                    if ctx.korean else ("WALK ME!", "LET'S GO~", "BORED..."))
            mi = int(t / 2) % len(msgs)
            draw.text((4, 13), msgs[mi],
                      font=ctx.font_small, fill=1, anchor="lm")

            # 마지막 산책 이후 경과 (우상단)
            count_txt = ""
            if ctx.beg_last_walk:
                diff = max(0.0, time.time() - ctx.beg_last_walk)
                d, rem = int(diff // 86400), diff % 86400
                h = int(rem // 3600)
                if d >= 1:
                    count_txt = f"{d}일째" if ctx.korean else f"{d}d ago"
                elif h >= 1:
                    count_txt = f"{h}시간째" if ctx.korean else f"{h}h ago"
            if count_txt:
                draw.text((110, 13), count_txt,
                          font=ctx.font_small, fill=1, anchor="rm")

            # 문 (오른쪽): 테두리 + 손잡이
            draw.rectangle((113, 16, 126, 31), outline=1)
            draw.point((116, 25), fill=1)

            # 서성이는 사람: 4초 주기 왕복 (삼각파), 문 앞에서 콩콩
            P = 4.0
            ph = (t % P) / P
            tri = 2 * ph if ph < 0.5 else 2 - 2 * ph        # 0→1→0
            px = int(18 + tri * (95 - 18))
            knocking = tri > 0.92                            # 문 앞 도착
            py = 19 if (knocking and int(t * 6) % 2 == 0) else 20
            leg = int(t / 0.3) % 2
            _draw_runner(draw, px, py, leg)
            if knocking:                                     # 두드림 표시
                draw.line((108, 20, 110, 18), fill=1)
                draw.line((108, 24, 110, 26), fill=1)

            key = ("beg", mi, px, py, leg, knocking, count_txt)

        elif state is ScreenState.CELEBRATE:
            # 산책 완료 축하: 제목+🎉(상단) / 시간(중앙, 2배 글씨) /
            # 만세 사람(하단 양옆). 만세 3회 — 팔 올릴 때마다 폭죽.
            INTRO, HALF, CYCLES = 0.6, 0.7, 3
            t = time.monotonic() - (ctx.celebrate_started_at or time.monotonic())
            total = INTRO + CYCLES * HALF * 2

            if t >= total:
                # 재생 종료 → 하트로 자동 복귀
                ctx.state = ScreenState.IDLE
                ctx.celebrate_started_at = None
                key = ("idle-return",)
            else:
                if t < INTRO:
                    up, burst_p = False, None            # 등장: 폭죽 없음
                    phase_id = -1
                else:
                    ph = (t - INTRO) / HALF              # 0.5마다 팔 전환
                    phase_id = int(ph)
                    up = phase_id % 2 == 0               # 짝수 구간 = 만세↑
                    burst_p = (ph - phase_id) if up else None

                # 상단: 제목 + 양옆 🎉 (터질 때만)
                # 케이스 마감이 물리 화면 위 ~8px을 가리므로 y>=8 영역에 배치
                draw.text((WIDTH // 2, 12), label,
                          font=ctx.font_title, fill=1, anchor="mm")
                if burst_p is not None:
                    _draw_popper(draw, 26, 15, burst_p, flip=False)
                    _draw_popper(draw, WIDTH - 27, 15, burst_p, flip=True)

                # 중앙: 산책 시간 (제목의 2배 크기)
                draw.text((WIDTH // 2, 24),
                          _fmt_elapsed(ctx.celebrate_duration),
                          font=ctx.font_time, fill=1, anchor="mm")

                # 하단 양옆: 만세 사람
                _draw_manse(draw, 3, 20, up)
                _draw_manse(draw, WIDTH - 13, 20, up)

                key = ("cheer", phase_id, up,
                       None if burst_p is None else int(burst_p * 8))

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
            # 좌측 고정 ● (점멸) + 5분에 한 바퀴 달리는 러너 트랙
            elapsed = ctx.elapsed()

            # 상단: 세그먼트 수(좌) · 경과 시간(우)
            # 케이스 마감이 물리 화면 위 ~8px을 가리므로 y>=8 영역에 배치
            if ctx.segment_count:
                draw.text((17, 14), f"{ctx.segment_count}seg",
                          font=ctx.font_small, fill=1, anchor="lm")
            draw.text((WIDTH - 2, 14), _fmt_elapsed(elapsed),
                      font=ctx.font_small, fill=1, anchor="rm")

            # 녹화 점: 왼쪽 고정, 0.5초 점멸 (가용 영역 세로 중앙)
            if blink:
                draw.ellipse((3, 14, 13, 24), fill=1)

            # 바닥 점선 트랙 — 화면 맨 아래 줄에 붙임
            for gx in range(18, WIDTH - 2, 4):
                draw.point((gx, 31), fill=1)

            # 러너: 1완주 = SEGMENT_SECONDS(5분). 다리는 0.3초마다 교차
            run_x0, run_x1 = 20, WIDTH - 10          # 출발(●에서 띄움) ~ 오른쪽 끝
            progress = (elapsed % SEGMENT_SECONDS) / SEGMENT_SECONDS
            run_x = int(run_x0 + progress * (run_x1 - run_x0))
            leg = int(time.monotonic() / 0.3) % 2
            _draw_runner(draw, run_x, 20, leg)

            key = ("rec", blink, leg, run_x,
                   int(elapsed), ctx.segment_count)

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
        fonts = _load_fonts()
        self.ctx = DisplayContext(*fonts)
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

    def show_begging(self, last_walk_epoch: float | None) -> None:
        """산책 조르기 화면으로 전환합니다. 다시 호출 주체(키 2)가
        IDLE로 되돌릴 때까지 유지됩니다."""
        with self._lock:
            self.ctx.beg_last_walk = last_walk_epoch
            self.ctx.state = ScreenState.BEGGING

    def celebrate(self, walked_sec: float) -> None:
        """산책 완료 축하 화면으로 전환합니다. 재생이 끝나면
        화면이 스스로 IDLE(하트)로 돌아갑니다."""
        with self._lock:
            self.ctx.celebrate_duration = walked_sec
            self.ctx.celebrate_started_at = time.monotonic()
            self.ctx.state = ScreenState.CELEBRATE

    def heart_burst(self) -> None:
        """IDLE 하트에서 6방향으로 작은 하트를 동시 발사합니다.

        어느 스레드에서 불러도 안전합니다. IDLE이 아닐 때 호출되면
        하트가 생성되긴 하나 그리지 않으므로 수명이 지나 사라집니다.
        """
        cx, cy = WIDTH / 2, HEIGHT / 2 + 4      # 중앙 하트 위치와 동일
        with self._lock:
            for ang in _BURST_DIRECTIONS_DEG:
                self.ctx.flying_hearts.append(_FlyingHeart(cx, cy, ang))
            self.ctx.fly_last_t = time.monotonic()

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
