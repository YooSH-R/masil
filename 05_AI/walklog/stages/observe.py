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

from .. import config
from .. import prompts as P
from ..console import step, warn
from ..gms import GMSClient, GMSError
from ..records import FrameMeta, FrameRecord

__all__ = ["FrameFailure", "observe_frame", "observe_frames", "observe_outdoor_frames"]

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


def observe_outdoor_frames(
    client: GMSClient,
    sampled: Sequence[FrameMeta],
    pool: Sequence[FrameMeta],
    *,
    max_replacements_per_slot: int = 1,
    allow_indoor_fallback: bool = True,
    spec: P.PromptSpec | None = None,
    max_attempts: int = DEFAULT_MAX_ATTEMPTS,
    base_delay: float = DEFAULT_BASE_DELAY,
    sleep: Callable[[float], None] = time.sleep,
) -> list[FrameRecord]:
    """표본을 관찰하되, 실내로 판정된 프레임은 인접 프레임으로 대체 시도한다.

    sampled: 표본 추출된 FrameMeta들. pool: 전체 FrameMeta (대체 후보 풀).
    실내 판정 프레임마다 시간상 가장 가까운 미사용 프레임을 최대
    max_replacements_per_slot회 대체 관찰한다 (슬롯당 VLM +1회 상한).
    대체본도 실내면 그 슬롯은 포기한다.

    안전판: allow_indoor_fallback=True(기본)면 최종 야외 기록 수와 무관하게
    항상 전체(실내 판정본 포함)를 반환한다 - 야외 기록이 config.SAMPLE_MIN
    미만이면 경고만 남긴다(기존 테스트 영상이 전부 실내라, 무조건 배제는
    파이프라인을 빈손으로 죽인다). allow_indoor_fallback=False면 야외
    기록만 반환한다(0개일 수 있음 - 호출부가 처리).

    반환 기록(allow_indoor_fallback=True 경로)에는 실내 판정본도 포함하되,
    다운스트림 제외는 호출부(CLI)가 outdoor() 필터로 수행한다 -
    frame_records.json에는 실내 기록도 남겨 감사(audit)가 가능해야 하기
    때문이다.
    """
    records, failures = observe_frames(
        client, sampled, spec=spec, max_attempts=max_attempts,
        base_delay=base_delay, sleep=sleep,
    )
    if failures:
        warn(f"{len(failures)}개 프레임은 관찰 자체에 실패해 대체 대상에서 제외됩니다.")

    used_paths = {r.meta.path for r in records} | {f.meta.path for f in failures}
    pool_timed = sorted(
        (m for m in pool if m.offset_seconds is not None),
        key=lambda m: m.offset_seconds,
    )

    final: list[FrameRecord] = []
    for record in records:
        if not record.is_indoor:
            final.append(record)
            continue

        anchor = record.meta.offset_seconds
        if anchor is None:
            warn(f"[실내 배제] {record.meta.name} 실내 판정이지만 경과 시각을 몰라 "
                 f"대체할 수 없습니다. 그대로 둡니다.")
            final.append(record)
            continue

        tried_paths = {record.meta.path}
        replaced: FrameRecord | None = None
        for _ in range(max_replacements_per_slot):
            candidates = [m for m in pool_timed
                         if m.path not in used_paths and m.path not in tried_paths]
            if not candidates:
                warn(f"[실내 배제] {record.meta.name} 대체할 야외 프레임 후보가 "
                     f"없어 포기합니다.")
                break
            nearest = min(candidates, key=lambda m: abs(m.offset_seconds - anchor))
            tried_paths.add(nearest.path)

            try:
                candidate_record = observe_frame(client, nearest, spec=spec)
            except Exception as exc:
                warn(f"[실내 배제] {record.meta.name} 대체 관찰 실패"
                     f"({nearest.name}): {exc}")
                continue

            used_paths.add(nearest.path)
            if not candidate_record.is_indoor:
                step(f"[실내 배제] {record.meta.name} 실내 판정 -> "
                     f"{nearest.name} 로 대체 관찰")
                replaced = candidate_record
                break
            warn(f"[실내 배제] {record.meta.name} 대체 후보 {nearest.name}도 "
                 f"실내로 판정되어 포기합니다.")

        final.append(replaced if replaced is not None else record)

    final.sort(key=lambda r: r.meta.sort_key)
    outdoor_only = [r for r in final if not r.is_indoor]

    if not allow_indoor_fallback:
        return outdoor_only

    if len(outdoor_only) < config.SAMPLE_MIN:
        warn(f"야외 기록이 {len(outdoor_only)}개로 최소 표본({config.SAMPLE_MIN})"
             f"보다 적습니다. 실내 기록을 포함해 그대로 진행합니다.")
    return final