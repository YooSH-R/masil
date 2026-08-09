#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ssd1309.py — 2.05" OLED (SSD1309, 128x32) SPI 하드웨어 드라이버

oled_test2.py의 SSD1309_SPI 클래스를 그대로 옮긴 하드웨어 계층입니다.
"화면에 무엇을 그릴지"는 모르고, "버퍼를 패널에 밀어넣는 방법"만 압니다.

계층 구조
    ssd1309.py      ← 이 파일. SPI/GPIO와 패널 초기화만 담당
    oled_status.py  ← 상태 화면 렌더링 + 백그라운드 갱신 스레드
    walkcam_oled.py ← 런처. 녹화 이벤트를 화면 상태로 연결

배선 (BCM 번호)
    DC  -> GPIO24,  RST -> GPIO25
    SPI0 (MOSI GPIO10, SCLK GPIO11, CE0 GPIO8)
"""

from __future__ import annotations

import time

import lgpio
import spidev

# ---- 배선에 맞춘 핀 (BCM 번호) ----
PIN_DC = 24
PIN_RST = 25
SPI_BUS = 0
SPI_DEV = 0
SPI_HZ = 8_000_000

WIDTH = 128
HEIGHT = 32
PAGES = HEIGHT // 8

INIT_CMDS = [
    0xAE,
    0xD5, 0x80,
    0xA8, 0x1F,
    0xD3, 0x00,
    0x40,
    0x8D, 0x10,
    0x20, 0x02,
    0xA1,
    0xC8,
    0xDA, 0x12,
    0x81, 0x66,
    0xD9, 0xF1,
    0xDB, 0x30,
    0xA4,
    0xA6,
    0xAF,
]


class SSD1309_SPI:
    """SSD1309 패널 저수준 제어. oled_test2.py와 동일한 검증된 구현입니다."""

    def __init__(self):
        try:
            self.h = lgpio.gpiochip_open(0)
        except lgpio.error:
            self.h = lgpio.gpiochip_open(4)
        lgpio.gpio_claim_output(self.h, PIN_DC, 0)
        lgpio.gpio_claim_output(self.h, PIN_RST, 1)

        self.spi = spidev.SpiDev()
        self.spi.open(SPI_BUS, SPI_DEV)
        self.spi.max_speed_hz = SPI_HZ
        self.spi.mode = 0

    def reset(self):
        lgpio.gpio_write(self.h, PIN_RST, 1); time.sleep(0.01)
        lgpio.gpio_write(self.h, PIN_RST, 0); time.sleep(0.01)
        lgpio.gpio_write(self.h, PIN_RST, 1); time.sleep(0.01)

    def cmd(self, c):
        lgpio.gpio_write(self.h, PIN_DC, 0)
        self.spi.writebytes([c])

    def data(self, buf):
        lgpio.gpio_write(self.h, PIN_DC, 1)
        for i in range(0, len(buf), 1024):
            self.spi.writebytes(buf[i:i + 1024])

    def init(self):
        self.reset()
        for c in INIT_CMDS:
            self.cmd(c)

    def display_on(self, on: bool = True):
        """패널 전원(표시)만 켜고 끕니다. 버퍼는 유지됩니다."""
        self.cmd(0xAF if on else 0xAE)

    def show(self, buf):
        idx = 0
        for p in range(PAGES):
            self.cmd(0xB0 + p)
            self.cmd(0x00)
            self.cmd(0x10)
            self.data(buf[idx:idx + WIDTH])
            idx += WIDTH

    def fill(self, on=True):
        self.show([0xFF if on else 0x00] * (WIDTH * PAGES))

    def image_to_buf(self, img) -> list[int]:
        """PIL 이미지를 페이지 버퍼로 변환만 합니다(전송 없음).

        oled_status.py가 '내용이 바뀌었을 때만 전송'하는 최적화를 하려면
        변환과 전송이 분리되어 있어야 합니다. Pi Zero W에서 녹화와 화면
        갱신이 동시에 돌기 때문에 불필요한 SPI 전송은 아끼는 편이 좋습니다.
        """
        img = img.convert("1")
        px = img.load()
        buf = [0] * (WIDTH * PAGES)
        for p in range(PAGES):
            for x in range(WIDTH):
                byte = 0
                for bit in range(8):
                    if px[x, p * 8 + bit]:
                        byte |= (1 << bit)
                buf[p * WIDTH + x] = byte
        return buf

    def image(self, img):
        self.show(self.image_to_buf(img))

    def close(self):
        try:
            self.fill(False)
            self.display_on(False)
        except Exception:
            pass
        self.spi.close()
        lgpio.gpiochip_close(self.h)
