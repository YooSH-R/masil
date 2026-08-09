#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make_sounds2.py — walkcam 이벤트 사운드 생성기 (2차분)

원본(최신)은 03_Embedded/Raspberry_Pi_Zero_W/Sound_Play/sounds/make_sound.py
입니다. 이 사본은 사운드 생성 당시 작업 폴더로 남은 것으로 보이며, wav 생성
로직을 고칠 때는 원본을 기준으로 삼으세요.

기존 docked.wav / warning.wav와 동일한 규격으로 만듭니다:
    44100 Hz · 16-bit · 스테레오 · 피크 50% (MAX98357A 왜곡 방지 레벨)

생성 목록
    undocked.wav       분리 확정 = 산책 시작 (상승 아르페지오, 경쾌)
    transfer_done.wav  전송 완료 (딩-동 성공음)
    startup.wav        부팅 완료 (따뜻한 화음 스웰)
    stalled.wav        녹화 이상 (짧은 삼연타 경고)
    low_battery.wav    배터리 부족 (하강 2음, 차분한 경고)

사용법
    python3 make_sounds2.py            # 현재 폴더에 wav 생성
"""

import wave

import numpy as np

RATE = 44100
PEAK = 0.5          # 앰프 왜곡 방지: 피크 50%
MIN_DUR = 2.0       # 모든 파일의 최소 길이(초)
LEAD_IN = 0.15      # 소리 앞의 무음(초) — 앰프 웨이크업 동안 서두 잘림 방지


def tone(freq: float, dur: float, vol: float = 1.0,
         attack: float = 0.01, release: float = 0.08) -> np.ndarray:
    """부드러운 엔벨로프 + 약한 배음의 단일 음."""
    n = int(RATE * dur)
    t = np.arange(n) / RATE
    # 기음 + 2배음(약하게) — 순수 사인보다 조금 따뜻한 음색
    y = np.sin(2 * np.pi * freq * t) + 0.25 * np.sin(2 * np.pi * freq * 2 * t)
    # 엔벨로프 (딸깍 소음 방지)
    env = np.ones(n)
    a = max(int(RATE * attack), 1)
    r = max(int(RATE * release), 1)
    env[:a] = np.linspace(0, 1, a)
    env[-r:] = np.linspace(1, 0, r)
    return y * env * vol


def silence(dur: float) -> np.ndarray:
    return np.zeros(int(RATE * dur))


def save(name: str, mono: np.ndarray) -> None:
    mono = mono / max(np.abs(mono).max(), 1e-9) * PEAK
    # 앞: 앰프 깨우기용 무음 / 뒤: 총 길이가 MIN_DUR이 되도록 채움
    lead = np.zeros(int(RATE * LEAD_IN))
    mono = np.concatenate([lead, mono])
    shortfall = int(RATE * MIN_DUR) - len(mono)
    if shortfall > 0:
        mono = np.concatenate([mono, np.zeros(shortfall)])
    pcm = (mono * 32767).astype(np.int16)
    stereo = np.column_stack([pcm, pcm]).ravel()
    with wave.open(name, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(stereo.tobytes())
    print(f"{name:20s} {len(mono)/RATE:.2f}s")


# ── 분리 확정 = 산책 시작: C5→E5→G5 상승 아르페지오 ──
save("undocked.wav", np.concatenate([
    tone(523.25, 0.12),           # C5
    tone(659.25, 0.12),           # E5
    tone(783.99, 0.28, vol=1.1),  # G5 (마지막 음을 길고 살짝 크게)
]))

# ── 전송 완료: 딩-동 (G5 → C6) ──
save("transfer_done.wav", np.concatenate([
    tone(783.99, 0.16),           # G5
    silence(0.04),
    tone(1046.5, 0.34, vol=1.1),  # C6
]))

# ── 부팅 완료: C-E-G 화음이 겹치며 스웰 ──
n = int(RATE * 0.7)
t = np.arange(n) / RATE
chord = (np.sin(2*np.pi*523.25*t)
         + np.sin(2*np.pi*659.25*t)
         + np.sin(2*np.pi*783.99*t))
env = np.minimum(t / 0.25, 1.0) * np.minimum((0.7 - t) / 0.3, 1.0)
save("startup.wav", chord * np.clip(env, 0, 1))

# ── 녹화 이상: 880Hz 짧은 삼연타 ──
beep = tone(880, 0.09, attack=0.005, release=0.02)
save("stalled.wav", np.concatenate([
    beep, silence(0.07), beep, silence(0.07), beep,
]))

# ── 배터리 부족: E5 → A4 하강 2음 ──
save("low_battery.wav", np.concatenate([
    tone(659.25, 0.2),
    silence(0.05),
    tone(440.0, 0.4),
]))