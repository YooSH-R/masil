#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
walkcam_ctl.py — SSH 터미널에서 키 하나로 촬영을 제어하는 컨트롤러

walkcam_key.py 데몬의 명령 파이프에 키 입력을 전달합니다.
데몬은 systemd로 이미 돌고 있고(하트 표시 중), 이 스크립트는
SSH 세션에서 실행하는 리모컨입니다.

사용법
    ssh piw@piw.local
    cd ~/walkcam && python3 walkcam_ctl.py

키
    Space / q   촬영 시작 ↔ 종료 (토글)
    1           하트 분출 이벤트 (대기 화면에서)
    2           산책 조르기 화면 토글 (대기 화면에서)
    3           현재 시각 화면 토글 (대기 화면에서)
    4           주인 마중 화면 토글 (대기 화면에서)
    x           컨트롤러 종료 (데몬은 계속 동작, 하트 유지)
    Q (대문자)  데몬까지 종료
"""

from __future__ import annotations

import sys
import termios
import tty
from pathlib import Path

CMD_FIFO = Path("/home/piw/walkcam/walkcam.cmd")


def send(cmd: str) -> bool:
    if not CMD_FIFO.is_fifo():
        print(f"\r\n[!] 명령 파이프가 없습니다: {CMD_FIFO}")
        print("[!] 데몬이 떠 있는지 확인: systemctl status walkcam-key\r")
        return False
    try:
        with open(CMD_FIFO, "w") as f:
            f.write(cmd + "\n")
        return True
    except Exception as e:
        print(f"\r\n[!] 전송 실패: {e}\r")
        return False


def main() -> int:
    if not sys.stdin.isatty():
        print("터미널에서 실행해야 합니다 (키 입력용).")
        return 1

    print("walkcam 컨트롤러 — Space/q: 촬영, 1: 하트, 2: 조르기, 3: 시계, 4: 마중, x: 나가기, Q: 데몬 종료")
    print("(촬영 시작음 = undocked.wav, 종료음 = docked.wav)")

    fd = sys.stdin.fileno()
    saved = termios.tcgetattr(fd)
    recording = False
    try:
        tty.setcbreak(fd)                    # 엔터 없이 1키 즉시 수신
        while True:
            ch = sys.stdin.read(1)
            if ch in (" ", "q"):
                if send("toggle"):
                    recording = not recording
                    state = "● 촬영 시작" if recording else "■ 촬영 종료"
                    print(f"\r{state}                    ")
            elif ch == "1":
                if send("burst"):
                    print("\r♥ 하트 분출!                    ")
            elif ch == "2":
                if send("beg"):
                    print("\r🐾 산책 조르기 화면 토글          ")
            elif ch == "3":
                if send("clock"):
                    print("\r🕐 시계 화면 토글                 ")
            elif ch == "4":
                if send("greet"):
                    print("\r💓 마중 화면 토글                 ")
            elif ch == "x":
                print("\r컨트롤러를 종료합니다 (데몬은 유지).")
                return 0
            elif ch == "Q":
                send("quit")
                print("\r데몬 종료 명령을 보냈습니다.")
                return 0
    except KeyboardInterrupt:
        print("\r컨트롤러를 종료합니다 (데몬은 유지).")
        return 0
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)


if __name__ == "__main__":
    sys.exit(main())
