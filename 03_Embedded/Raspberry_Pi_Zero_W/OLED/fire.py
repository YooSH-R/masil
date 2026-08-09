#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
oled_fireworks.py — 128x32 OLED 폭죽 애니메이션 (무한 반복)

ssd1309.py 드라이버를 재사용합니다. oled_test2.py의 씬들과 같은 방식으로
동작하며, 이 파일 하나만 단독 실행하면 됩니다.

동작
    1) 바닥에서 로켓이 발사되어 위로 올라감 (꼬리 궤적)
    2) 정점에서 폭발 — 입자들이 사방으로 퍼짐
    3) 입자들은 중력으로 떨어지며 수명이 다하면 깜빡이다 사라짐
    4) 동시에 여러 발이 겹치도록 무작위 간격으로 계속 발사

흑백 1비트 디스플레이라 '페이드아웃'은 밝기 대신
수명 끝에서 깜빡임(blink)으로 표현합니다.

실행:  python3 oled_fireworks.py
종료:  Ctrl+C

옵션:
    python3 oled_fireworks.py --fps 25        # 프레임 속도 (기본 25)
    python3 oled_fireworks.py --max-shells 3  # 동시에 뜨는 폭죽 수 (기본 3)
"""

from __future__ import annotations

import argparse
import math
import random
import time

from PIL import Image, ImageDraw

from ssd1309 import HEIGHT, WIDTH, SSD1309_SPI

GRAVITY = 18.0          # 픽셀/초^2. 32픽셀 높이에 맞춘 약한 중력
PARTICLES_PER_SHELL = 14
PARTICLE_LIFE = (0.9, 1.5)   # 입자 수명 범위(초)
BLINK_TAIL = 0.4             # 수명 마지막 이 구간은 깜빡이며 사라짐


class Particle:
    """폭발 후 흩어지는 불꽃 조각 하나."""

    def __init__(self, x: float, y: float):
        angle = random.uniform(0, 2 * math.pi)
        speed = random.uniform(8.0, 22.0)
        self.x = x
        self.y = y
        self.vx = math.cos(angle) * speed
        self.vy = math.sin(angle) * speed * 0.6  # 화면이 납작하니 세로는 눌러줌
        self.life = random.uniform(*PARTICLE_LIFE)
        self.age = 0.0

    def update(self, dt: float) -> None:
        self.age += dt
        self.vy += GRAVITY * dt
        self.x += self.vx * dt
        self.y += self.vy * dt

    @property
    def alive(self) -> bool:
        return self.age < self.life and -2 < self.x < WIDTH + 2 and self.y < HEIGHT + 2

    def visible(self) -> bool:
        """수명 막바지에는 깜빡이며 사라지는 느낌을 냅니다."""
        remain = self.life - self.age
        if remain > BLINK_TAIL:
            return True
        return int(self.age * 12) % 2 == 0


class Shell:
    """로켓 발사 → 폭발 → 입자 소멸까지 폭죽 한 발의 전체 수명."""

    def __init__(self):
        self.x = random.uniform(WIDTH * 0.15, WIDTH * 0.85)
        self.y = float(HEIGHT - 1)
        self.apex = random.uniform(4.0, HEIGHT * 0.45)  # 폭발 고도
        self.vy = -random.uniform(28.0, 38.0)           # 상승 속도
        self.exploded = False
        self.particles: list[Particle] = []
        self.trail: list[tuple[int, int]] = []          # 로켓 꼬리 궤적

    def update(self, dt: float) -> None:
        if not self.exploded:
            self.trail.append((int(self.x), int(self.y)))
            if len(self.trail) > 4:
                self.trail.pop(0)
            self.y += self.vy * dt
            if self.y <= self.apex:
                self.exploded = True
                self.particles = [
                    Particle(self.x, self.y) for _ in range(PARTICLES_PER_SHELL)
                ]
        else:
            for p in self.particles:
                p.update(dt)
            self.particles = [p for p in self.particles if p.alive]

    @property
    def done(self) -> bool:
        return self.exploded and not self.particles

    def draw(self, draw: ImageDraw.ImageDraw) -> None:
        if not self.exploded:
            # 로켓 본체 + 점점 옅어지는 꼬리(1픽셀 점을 띄엄띄엄)
            draw.point((int(self.x), int(self.y)), fill=1)
            for i, (tx, ty) in enumerate(reversed(self.trail)):
                if i % 2 == 0:
                    draw.point((tx, ty + i), fill=1)
        else:
            for p in self.particles:
                if p.visible():
                    draw.point((int(p.x), int(p.y)), fill=1)
            # 폭발 직후 짧은 섬광(원형 링)
            if self.particles:
                youngest = min(p.age for p in self.particles)
                if youngest < 0.12:
                    r = int(youngest * 40) + 2
                    cx, cy = int(self.x), int(self.y)
                    draw.ellipse((cx - r, cy - r, cx + r, cy + r), outline=1)


def main() -> int:
    parser = argparse.ArgumentParser(description="OLED 폭죽 애니메이션")
    parser.add_argument("--fps", type=int, default=25, help="프레임 속도 (기본 25)")
    parser.add_argument("--max-shells", type=int, default=3,
                        help="동시에 표시할 최대 폭죽 수 (기본 3)")
    args = parser.parse_args()

    frame_dt = 1.0 / max(1, args.fps)

    oled = SSD1309_SPI()
    oled.init()

    shells: list[Shell] = [Shell()]
    next_launch = time.monotonic() + random.uniform(0.3, 1.0)

    print("폭죽 애니메이션 시작 — Ctrl+C로 종료")
    try:
        last = time.monotonic()
        while True:
            now = time.monotonic()
            dt = min(now - last, 0.1)  # 프레임 드랍 시 물리 폭주 방지
            last = now

            # 무작위 간격으로 새 폭죽 발사
            if now >= next_launch and len(shells) < args.max_shells:
                shells.append(Shell())
                next_launch = now + random.uniform(0.4, 1.4)

            for s in shells:
                s.update(dt)
            shells = [s for s in shells if not s.done]
            if not shells:
                shells.append(Shell())

            img = Image.new("1", (WIDTH, HEIGHT), 0)
            draw = ImageDraw.Draw(img)
            for s in shells:
                s.draw(draw)
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
