#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
audio.py — WalkCam 효과음 재생 모듈

데몬(walkcamd)의 오디오 하위 시스템입니다. MAX98357A + ALSA 조합을
전제로, aplay 서브프로세스를 이용해 짧은 효과음 wav를 재생합니다.

설계 원칙
    - 논블로킹: play()는 즉시 반환. 소리 재생이 녹화나 화면을
      멈추게 해서는 안 됩니다.
    - 단일 재생: 새 효과음이 오면 재생 중이던 소리는 끊고 교체.
      효과음이 겹쳐 지저분해지는 것을 막습니다.
    - keep-alive: MAX98357A는 I2S 클럭이 끊기면 절전으로 들어가고,
      깨어날 때마다 팝(치직) 노이즈를 냅니다. 플레이어가 살아 있는
      동안 무음 스트림을 상시 재생해 앰프를 깨워둠으로써 재생
      시작/끝의 팝을 원천 차단합니다. (/etc/asound.conf 의 dmix
      설정이 전제 — 무음과 효과음이 동시에 열려야 하므로)
    - 실패 무해: 오디오가 안 되는 상황(카드 미인식 등)에서도
      예외가 데몬을 죽이지 않고 경고 로그만 남깁니다.

사용 예
    from audio import SoundPlayer
    audio = SoundPlayer("sounds")      # keep-alive 자동 시작
    audio.set_volume(60)               # 검증된 기본 음량
    audio.play("docked")               # sounds/docked.wav (논블로킹)
    ...
    audio.close()                      # keep-alive 포함 전체 정리

단독 테스트
    python3 audio.py                   # 모든 효과음을 순서대로 재생
    python3 audio.py boot happy        # 지정한 것만 재생

전제: /etc/asound.conf 로 기본 장치가 sndrpihifiberry로 고정되어
있으면 device 인자가 필요 없습니다. 고정하지 않았다면
SoundPlayer(device="plughw:sndrpihifiberry") 로 지정하세요.
"""

from __future__ import annotations

import logging
import subprocess
import threading
import time
from pathlib import Path


class SoundPlayer:
    """aplay 기반 효과음 재생기 (논블로킹, 단일 재생)."""

    def __init__(self, sounds_dir: str | Path = "sounds",
                 device: str | None = None,
                 keep_alive: bool = True,
                 volume: int | None = 60,
                 log: logging.Logger | None = None):
        self.sounds_dir = Path(sounds_dir)
        self.device = device
        self.log = log or logging.getLogger("audio")
        self._proc: subprocess.Popen | None = None
        self._keepalive: subprocess.Popen | None = None
        self._lock = threading.Lock()
        self.enabled = True   # 상태 기계가 음소거하고 싶을 때 False

        if not self.sounds_dir.is_dir():
            self.log.warning("효과음 디렉토리가 없습니다: %s", self.sounds_dir)

        if volume is not None:
            self.set_volume(volume)
        if keep_alive:
            self._start_keepalive()

    # ── keep-alive (앰프 팝 노이즈 방지) ────────────────

    def _start_keepalive(self) -> None:
        """무음 스트림을 상시 재생해 I2S 클럭을 유지합니다.

        dmix 설정 덕분에 효과음과 동시에 재생될 수 있고,
        데이터가 전부 0이라 스피커에서는 아무 소리도 나지 않습니다.
        """
        cmd = ["aplay", "-q", "-t", "raw",
               "-f", "S16_LE", "-r", "44100", "-c", "2"]
        if self.device:
            cmd += ["-D", self.device]
        cmd.append("/dev/zero")
        try:
            self._keepalive = subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            self.log.debug("오디오 keep-alive 시작 (pid=%d)",
                           self._keepalive.pid)
        except Exception:
            self.log.warning("keep-alive 시작 실패 — 재생 시작/끝에 "
                             "팝 노이즈가 날 수 있습니다")
            self._keepalive = None

    def _stop_keepalive(self) -> None:
        if self._keepalive is not None and self._keepalive.poll() is None:
            self._keepalive.terminate()
            try:
                self._keepalive.wait(timeout=1.0)
            except subprocess.TimeoutExpired:
                self._keepalive.kill()
        self._keepalive = None

    # ── 재생 ─────────────────────────────────────────────

    def play(self, name: str) -> bool:
        """sounds_dir/<name>.wav 를 논블로킹으로 재생.

        재생 중이던 소리는 끊고 새 소리로 교체합니다.
        성공적으로 재생을 '시작'했으면 True.
        """
        if not self.enabled:
            return False

        path = self.sounds_dir / f"{name}.wav"
        if not path.is_file():
            self.log.warning("효과음 파일 없음: %s", path)
            return False

        cmd = ["aplay", "-q"]
        if self.device:
            cmd += ["-D", self.device]
        cmd.append(str(path))

        with self._lock:
            self._stop_locked()
            try:
                self._proc = subprocess.Popen(
                    cmd,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                return True
            except FileNotFoundError:
                self.log.error("aplay를 찾을 수 없습니다 (alsa-utils 설치 필요)")
            except Exception:
                self.log.exception("효과음 재생 실패: %s", name)
            self._proc = None
            return False

    def stop(self) -> None:
        """재생 중인 소리를 즉시 중단."""
        with self._lock:
            self._stop_locked()

    def _stop_locked(self) -> None:
        if self._proc is not None and self._proc.poll() is None:
            self._proc.terminate()
            try:
                self._proc.wait(timeout=0.5)
            except subprocess.TimeoutExpired:
                self._proc.kill()
        self._proc = None

    def is_playing(self) -> bool:
        with self._lock:
            return self._proc is not None and self._proc.poll() is None

    # ── 음량 ─────────────────────────────────────────────

    def set_volume(self, percent: int) -> bool:
        """softvol Master 음량 설정 (0~100).

        /etc/asound.conf 의 softvol 설정이 전제입니다. 실패해도
        재생 자체는 가능하므로 경고만 남깁니다.
        """
        percent = max(0, min(100, int(percent)))
        try:
            subprocess.run(
                ["amixer", "-q", "set", "Master", f"{percent}%"],
                check=True, timeout=3,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            return True
        except Exception:
            self.log.warning("음량 설정 실패 (softvol 미설정?): %d%%", percent)
            return False

    # ── 수명 ─────────────────────────────────────────────

    def close(self) -> None:
        self.stop()
        self._stop_keepalive()


# ─────────────────────────────────────────────────────────
# 단독 테스트
# ─────────────────────────────────────────────────────────

if __name__ == "__main__":
    import sys

    logging.basicConfig(level=logging.INFO, format="%(message)s")
    player = SoundPlayer("sounds")

    names = sys.argv[1:] or [
        "docked", "warning"
    ]
    for n in names:
        print(f"[재생] {n}")
        if player.play(n):
            # 테스트에서는 겹치지 않게 재생이 끝날 때까지 대기
            while player.is_playing():
                time.sleep(0.05)
            time.sleep(0.4)
    player.close()
    print("완료")
