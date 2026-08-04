"""콘솔 출력 관련 처리.

[왜 별도 파일인가]
Windows 기본 콘솔 인코딩(cp949)에서는 한글 출력이 UnicodeEncodeError로 죽는다.
분할 전에는 이 처리가 파이프라인 파일 맨 위에 붙어 있어서, 그 파일을 거치지 않는
경로(테스트, 다른 스크립트)에서는 적용되지 않았다.

이 모듈은 import되는 순간 인코딩을 고친다. 부작용이 있는 import이지만 의도한 것이다.
warn()이 한글을 stderr로 내보내므로, warn을 쓰는 모듈은 자동으로 안전해야 한다.
"""

from __future__ import annotations

import sys

__all__ = ["enable_utf8", "warn", "step", "info"]


def enable_utf8() -> None:
    """표준 출력/에러 스트림을 UTF-8로 재설정한다. 여러 번 불러도 안전하다."""
    if sys.platform != "win32":
        return
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            # 파이프로 리다이렉트된 경우 등. 실패해도 진행을 막지 않는다.
            pass


enable_utf8()


def warn(message: str) -> None:
    """경고를 stderr로 출력한다.

    조용히 잘못된 값으로 진행하는 것을 막기 위한 통로다.
    예: 프레임 파일명에서 시각을 못 읽으면 정렬이 무너지는데,
    전에는 아무 표시 없이 0으로 처리되어 순서가 뒤섞인 일지가 나왔다.

    지금은 print 한 줄이다. 나중에 logging으로 바꾸더라도 이 파일만 고치면 된다.
    """
    print(f"[경고] {message}", file=sys.stderr)


def step(message: str) -> None:
    """진행 상황을 stderr로 출력한다.

    stdout에는 최종 결과물만 남긴다. `python run_walk_log.py > log.md` 처럼
    결과만 파일로 받고 싶을 때 진행 로그가 섞이지 않는다.
    (레거시 두 스크립트가 이미 이 방식을 쓰고 있었다)
    """
    print(message, file=sys.stderr)


def info(message: str) -> None:
    """최종 결과를 stdout으로 출력한다."""
    print(message)