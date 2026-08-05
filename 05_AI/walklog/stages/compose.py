"""Stage 2 - 관찰 기록 -> 산책 일지.

파일 이름을 diary가 아니라 compose로 둔 이유: prompts/diary.py와 구별하기
위해서다. 이 파일은 "쓰는 행위"를, 저쪽은 "무엇을 쓰라는 지시"를 담는다.
스테이지 파일 이름은 observe / compose / illustrate 로 동사를 통일했다.
"""

from __future__ import annotations

from datetime import date
from typing import Sequence

from .. import prompts as P
from ..console import step
from ..gms import GMSClient
from ..records import UNKNOWN, FrameRecord, to_json_lines, usable, walk_duration

__all__ = ["ComposeError", "compose_walk_log"]


class ComposeError(RuntimeError):
    """일지를 쓸 수 있는 기록이 없다."""


def compose_walk_log(
    client: GMSClient,
    records: Sequence[FrameRecord],
    *,
    walk_date: str | None = None,
    duration: str | None = None,
    style: str = P.DEFAULT_DIARY_STYLE,
) -> str:
    """관찰 기록을 한 편의 산책 일지로 엮는다.

    unreadable 필터가 records.usable() 한 곳으로 모였다. 분할 전에는 이 한 줄이
    write_walk_log와 make_image_prompt에 각각 있어서 조건이 갈릴 위험이 있었다.

    duration을 주지 않으면 마지막 프레임의 경과 시각을 쓴다.
    walk_date를 주지 않으면 오늘 날짜를 쓴다(분할 전 동작과 같다).
    """
    writable = usable(records)
    if not writable:
        raise ComposeError(
            f"일지를 쓸 수 있는 기록이 없습니다 "
            f"(전체 {len(records)}개가 모두 unreadable). "
            f"프레임 화질이나 MAX_SIDE 설정을 확인하세요."
        )

    resolved_duration = duration or walk_duration(writable)
    if resolved_duration == UNKNOWN:
        step("  경과 시각을 아는 프레임이 없어 소요시간을 '불명'으로 넘깁니다")

    step(f"[Stage 2] 일지 작성 (문체={style}, 프레임 {len(writable)}개)")
    return client.generate_text(
        P.diary_spec(style),
        tag=f"diary_{style}",
        walk_date=walk_date or date.today().isoformat(),
        duration=resolved_duration,
        n_frames=len(writable),
        json_lines=to_json_lines(writable),
    )