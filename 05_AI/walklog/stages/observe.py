"""Stage 1 - 프레임 -> 관찰 기록.

[분할 전에서 바뀐 점]
1. 재시도. 분할 전에는 프레임 하나가 실패하면 print 후 그냥 건너뛰었다.
   프레임 수만큼 연속 호출하는 경로에서 일시적 429/5xx 한 번에 관찰 기록이
   사라진다. GMSError.retryable 을 보고 재시도한다.
2. 실패 목록 반환. 분할 전에는 몇 개가 왜 빠졌는지가 stderr에만 남아
   호출부가 알 수 없었다. 이제 FrameFailure 목록을 함께 돌려준다.
3. shot_datetime / location 전달. 분할 전 main()은 describe_frame(f)만 불러서
   두 값이 항상 "불명"이었다. 이제 FrameMeta.prompt_vars()가 넘긴다.
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Callable, Sequence

from .. import prompts as P
from ..console import step, warn
from ..gms import GMSClient, GMSError
from ..records import FrameMeta, FrameRecord

__all__ = ["FrameFailure", "observe_frame", "observe_frames"]

# 재시도 간격. 429는 잠깐 기다리면 풀리는 경우가 많다.
DEFAULT_MAX_ATTEMPTS = 3
DEFAULT_BASE_DELAY = 2.0


@dataclass(frozen=True)
class FrameFailure:
    """관찰 기록을 못 만든 프레임."""

    meta: FrameMeta
    error: Exception
    attempts: int

    def __str__(self) -> str:
        return f"{self.meta.name}: {self.error} (시도 {self.attempts}회)"


def observe_frame(
    client: GMSClient,
    meta: FrameMeta,
    *,
    spec: P.PromptSpec | None = None,
) -> FrameRecord:
    """프레임 한 장을 관찰 기록으로 만든다. 실패하면 예외를 그대로 올린다.

    spec을 주면 FRAME_EXTRACT 대신 쓴다. thinking_budget이나 temperature를
    바꿔 실험할 때 쓴다. 예: P.FRAME_EXTRACT.tweak(thinking_budget=0)
    """
    observation = client.generate_json(
        spec or P.FRAME_EXTRACT,
        image_paths=[meta.path],
        tag=f"frame_{meta.index if meta.index is not None else meta.name}",
        **meta.prompt_vars(),
    )
    return FrameRecord(observation=observation, meta=meta)


def observe_frames(
    client: GMSClient,
    metas: Sequence[FrameMeta],
    *,
    spec: P.PromptSpec | None = None,
    max_attempts: int = DEFAULT_MAX_ATTEMPTS,
    base_delay: float = DEFAULT_BASE_DELAY,
    sleep: Callable[[float], None] = time.sleep,
) -> tuple[list[FrameRecord], list[FrameFailure]]:
    """프레임 목록을 순서대로 처리한다.

    한 프레임의 실패가 전체를 멈추지 않는다는 분할 전 동작을 유지하되,
    재시도 가능한 실패는 다시 시도한다.

    sleep을 인자로 받는 이유: 테스트가 실제로 기다리지 않게 하기 위해서다.
    """
    records: list[FrameRecord] = []
    failures: list[FrameFailure] = []
    total = len(metas)

    for position, meta in enumerate(metas, 1):
        step(f"[{position}/{total}] {meta.name}")

        for attempt in range(1, max_attempts + 1):
            try:
                records.append(observe_frame(client, meta, spec=spec))
                break
            except GMSError as exc:
                retryable = getattr(exc, "retryable", False)
                if not retryable or attempt == max_attempts:
                    failures.append(FrameFailure(meta, exc, attempt))
                    warn(f"{meta.name} 건너뜀: {exc}")
                    break
                delay = base_delay * (2 ** (attempt - 1))
                step(f"  재시도 {attempt}/{max_attempts - 1} ({delay:.0f}초 후): {exc}")
                sleep(delay)
            except Exception as exc:  # 파일 읽기 실패, 인코딩 실패 등
                failures.append(FrameFailure(meta, exc, attempt))
                warn(f"{meta.name} 건너뜀: {exc}")
                break

    records.sort(key=lambda r: r.meta.sort_key)
    return records, failures