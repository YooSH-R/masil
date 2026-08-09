#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
oled_heart_burst.py — 중앙 고정 하트 + 6방향 하트 분출 애니메이션

요구사항 구현
    1) 화면 정중앙에 디스플레이 높이에 맞는 큰 하트 1개 고정
    2) 그 하트에서 작은 하트들이 '뿅' 튀어나옴
    3) 튀어나온 하트는 날아가면서 크기가 점점 커짐 (3단계)
    4) 중력의 영향을 받아 포물선을 그리며 아래로 떨어짐
    5) 방향은 중앙 기준 6방향: 좌 / 우 / 좌상 / 우상 / 좌하 / 우하
       (순서대로 돌아가며 발사되어 6방향이 골고루 나옵니다)
    6) 날아가는 동안 위아래로 살짝 흔들림(wobble)

ssd1309.py 드라이버를 재사용합니다.

실행:  python3 oled_heart_burst.py
종료:  Ctrl+C

옵션:
    --fps 25          프레임 속도 (기본 25)
    --max-hearts 8    동시에 날아다니는 하트 수 (기본 8)
    --gravity 22      중력 세기. 클수록 포물선이 급함 (기본 22)
    --no-rotate       기본은 180도 뒤집어 출력. 원래 방향은 이 옵션 사용
"""

from __future__ import annotations

import argparse
import math
import random
import time

from PIL import Image, ImageDraw

from ssd1309 import HEIGHT, WIDTH, SSD1309_SPI

# ─────────────────────────────────────────────────────────
# 도트맵 정의 — 'X'가 켜지는 픽셀. 모양은 여기서 바로 수정 가능.
# ─────────────────────────────────────────────────────────

# 중앙 고정 하트: 25x23. 32픽셀 높이 화면을 거의 채우는 크기
# (위아래 4~5픽셀 여백). 하트 곡선 방정식으로 생성한 도트맵입니다.
_CENTER_HEART = [
    "....XXXXX.......XXXXX....",
    "..XXXXXXXXXX.XXXXXXXXXX..",
    ".XXXXXXXXXXXXXXXXXXXXXXX.",
    ".XXXXXXXXXXXXXXXXXXXXXXX.",
    "XXXXXXXXXXXXXXXXXXXXXXXXX",
    "XXXXXXXXXXXXXXXXXXXXXXXXX",
    "XXXXXXXXXXXXXXXXXXXXXXXXX",
    "XXXXXXXXXXXXXXXXXXXXXXXXX",
    "XXXXXXXXXXXXXXXXXXXXXXXXX",
    "XXXXXXXXXXXXXXXXXXXXXXXXX",
    "XXXXXXXXXXXXXXXXXXXXXXXXX",
    ".XXXXXXXXXXXXXXXXXXXXXXX.",
    ".XXXXXXXXXXXXXXXXXXXXXXX.",
    "..XXXXXXXXXXXXXXXXXXXXX..",
    "...XXXXXXXXXXXXXXXXXXX...",
    "....XXXXXXXXXXXXXXXXX....",
    "....XXXXXXXXXXXXXXXXX....",
    "......XXXXXXXXXXXXX......",
    ".......XXXXXXXXXXX.......",
    "........XXXXXXXXX........",
    "..........XXXXX..........",
    "...........XXX...........",
    "............X............",
]

# 날아가는 작은 하트: 커지는 3단계
_SMALL_HEART_ART = [
    [   # size 0: 3x3 — 갓 튀어나온 순간
        "X.X",
        "XXX",
        ".X.",
    ],
    [   # size 1: 5x5 — 커지는 중
        ".X.X.",
        "XXXXX",
        "XXXXX",
        ".XXX.",
        "..X..",
    ],
    [   # size 2: 7x7 — 완전히 커진 상태
        ".XX.XX.",
        "XXXXXXX",
        "XXXXXXX",
        "XXXXXXX",
        ".XXXXX.",
        "..XXX..",
        "...X...",
    ],
]


def _art_to_pixels(art: list[str]) -> list[tuple[int, int]]:
    """문자열 그림을 중심 기준 (dx, dy) 오프셋 목록으로 변환."""
    h = len(art)
    w = len(art[0])
    return [
        (x - w // 2, y - h // 2)
        for y, row in enumerate(art)
        for x, ch in enumerate(row)
        if ch == "X"
    ]


_CENTER_PIXELS = _art_to_pixels(_CENTER_HEART)
_SMALL_PIXELS = [_art_to_pixels(a) for a in _SMALL_HEART_ART]

# ─────────────────────────────────────────────────────────
# 발사 방향 정의 — 요구사항의 6방향 (화면 좌표: y는 아래가 +)
# 각도는 수학 좌표 기준이며 vy 계산에서 화면 좌표로 뒤집습니다.
# ─────────────────────────────────────────────────────────

_DIRECTIONS_DEG = [
    180,   # 좌
    0,     # 우
    135,   # 좌상
    45,    # 우상
    225,   # 좌하
    315,   # 우하
]

GROW_STEP = 0.35     # 이 시간(초)마다 하트가 한 단계 커짐
WOBBLE_AMP = 1.6     # 위아래 흔들림 진폭(픽셀) — '약간씩' 흔들리는 수준
SPEED_RANGE = (16.0, 24.0)


class FlyingHeart:
    """중앙 하트에서 튀어나와 포물선을 그리는 작은 하트."""

    def __init__(self, cx: float, cy: float, angle_deg: float, gravity: float):
        rad = math.radians(angle_deg)
        speed = random.uniform(*SPEED_RANGE)
        # 중앙 하트 가장자리에서 시작하는 느낌을 주기 위해
        # 발사 방향으로 하트 반폭만큼(가로 13 / 세로 10픽셀) 떨어진
        # 지점에서 출발합니다. 중앙 하트를 키우면 이 값도 같이 키우세요.
        self.x = cx + math.cos(rad) * 13
        self.y = cy - math.sin(rad) * 10
        self.vx = math.cos(rad) * speed
        self.vy = -math.sin(rad) * speed   # 화면 좌표(y 아래가 +)로 변환
        self.gravity = gravity
        self.age = 0.0
        self.wobble_phase = random.uniform(0, 2 * math.pi)
        self.wobble_speed = random.uniform(6.0, 9.0)

    def update(self, dt: float) -> None:
        self.age += dt
        self.vy += self.gravity * dt       # 중력 → 포물선 낙하
        self.x += self.vx * dt
        self.y += self.vy * dt

    @property
    def alive(self) -> bool:
        # 화면을 완전히 벗어나면 제거 (아래로 떨어져 나가는 경우 포함)
        return -8 < self.x < WIDTH + 8 and self.y < HEIGHT + 8

    def size_index(self) -> int:
        """날아가면서 점점 커짐: 0 → 1 → 2 단계에서 고정."""
        return min(2, int(self.age / GROW_STEP))

    def draw(self, draw: ImageDraw.ImageDraw) -> None:
        # 위아래로 약간씩 흔들리는 오프셋 (요구사항 6)
        wobble = WOBBLE_AMP * math.sin(
            self.wobble_phase + self.age * self.wobble_speed
        )
        cx = int(self.x)
        cy = int(self.y + wobble)
        for dx, dy in _SMALL_PIXELS[self.size_index()]:
            px, py = cx + dx, cy + dy
            if 0 <= px < WIDTH and 0 <= py < HEIGHT:
                draw.point((px, py), fill=1)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="중앙 하트에서 6방향으로 하트가 분출되는 애니메이션"
    )
    parser.add_argument("--fps", type=int, default=25, help="프레임 속도 (기본 25)")
    parser.add_argument("--max-hearts", type=int, default=8,
                        help="동시에 날아다니는 최대 하트 수 (기본 8)")
    parser.add_argument("--gravity", type=float, default=22.0,
                        help="중력 세기(px/s^2). 클수록 빨리 떨어짐 (기본 22)")
    parser.add_argument("--no-rotate", action="store_true",
                        help="180도 회전 없이 원래 방향으로 출력")
    args = parser.parse_args()

    frame_dt = 1.0 / max(1, args.fps)
    center_x = WIDTH / 2
    center_y = HEIGHT / 2

    oled = SSD1309_SPI()
    oled.init()

    hearts: list[FlyingHeart] = []
    direction_idx = 0                       # 6방향을 순서대로 순환
    next_spawn = time.monotonic() + 0.3

    print("하트 분출 애니메이션 시작 — Ctrl+C로 종료")
    try:
        last = time.monotonic()
        while True:
            now = time.monotonic()
            dt = min(now - last, 0.1)
            last = now

            # 6방향을 돌아가며 새 하트 발사
            if now >= next_spawn and len(hearts) < args.max_hearts:
                angle = _DIRECTIONS_DEG[direction_idx]
                direction_idx = (direction_idx + 1) % len(_DIRECTIONS_DEG)
                hearts.append(
                    FlyingHeart(center_x, center_y, angle, args.gravity)
                )
                next_spawn = now + random.uniform(0.18, 0.4)

            for h in hearts:
                h.update(dt)
            hearts = [h for h in hearts if h.alive]

            img = Image.new("1", (WIDTH, HEIGHT), 0)
            draw = ImageDraw.Draw(img)

            # 1) 중앙 고정 하트 (항상 표시)
            for dx, dy in _CENTER_PIXELS:
                draw.point((int(center_x) + dx, int(center_y) + dy), fill=1)

            # 2) 날아다니는 하트들
            for h in hearts:
                h.draw(draw)

            # 패널 장착 방향에 맞춰 화면 전체를 180도 회전해서 출력.
            # (물리는 그대로 두고 최종 프레임만 뒤집는 방식이라
            #  중력·포물선 로직은 손대지 않아도 됩니다)
            if not args.no_rotate:
                img = img.transpose(Image.ROTATE_180)

            oled.image(img)

            elapsed = time.monotonic() - now
            if elapsed < frame_dt:
                time.sleep(frame_dt - elapsed)
    except KeyboardInterrupt:
        print("\n종료합니다.")
    finally:
        oled.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
