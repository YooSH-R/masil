"""산책 일지 생성 CLI.

  Stage 0  프레임 추출 -> 표본 추출 (시간 구간 중앙 밴드에서 무작위 1장, API 없음)
  Stage 1  표본 프레임 -> 관찰 기록 (VLM)
  Stage 2  관찰 기록 -> 산책 일지 (LLM)
  Stage 3  일지(이야기) + 관찰 기록 -> 감성 이미지 한 장 (--story-image, LLM + 이미지 모델)

사용:
    python run_walk_log.py
    python run_walk_log.py --check                     # 프록시 지원 진단만
    python run_walk_log.py --style emotional
    python run_walk_log.py --started-at 2026-07-28T08:12:03
    python run_walk_log.py --records outputs/2026-07-28/frame_records.json --no-observe
    python run_walk_log.py --limit 2 --dump-payload    # 2장만, 요청 덤프
    python run_walk_log.py                              # 표본 자동 계산 (전체의 약 10%, 4~12장)
    python run_walk_log.py --quarters 6                 # 등분 수를 6으로 직접 지정
    python run_walk_log.py --sample-ratio 0.15           # 자동 계산 비율만 바꿈 (등분 수는 유지)
    python run_walk_log.py --no-sample                  # 표본 추출 없이 전부 처리
    python run_walk_log.py --style story --story-image --image-style watercolor
                                                         # 이야기 문체 + 감성 이미지 한 장
    python run_walk_log.py --session 2                  # 세션 번호를 직접 지정
    python run_walk_log.py --allow-indoor                # 실내 프레임 배제/대체를 끈다 (실내 테스트 영상용)

[분할 전에서 바뀐 점]
1. --started-at / --location 이 생겼다. 분할 전에는 shot_datetime이 항상 "불명"이라
   프롬프트의 "촬영 일시가 주어졌다면 time_of_day를 그 값으로" 지시가 발동하지 않았다.
2. --records + --no-observe 로 Stage 1을 건너뛰고 일지만 다시 쓸 수 있다.
   문체를 비교하려고 API를 다시 부를 필요가 없다.
3. 결과가 outputs/<날짜>/session<N>/ 아래에 쌓인다. 실행 위치에 덮어쓰지 않는다.
4. 실패한 프레임 목록을 마지막에 요약한다.

[세션 폴더]
하루에 산책을 여러 번 다녀올 수 있다. outputs/<날짜>/ 에 바로 결과를 쓰면
두 번째 산책이 첫 번째 산책 기록을 덮어쓴다. 그래서 실행마다 그날의
세션 번호를 하나씩 올려 session1, session2, ... 로 나눈다(--session으로
직접 지정하지 않는 한). 관찰 기록·일지·감성 이미지가 모두 같은 세션
폴더 안에 함께 쌓인다.

[표본 추출을 Stage 1 앞에 둔 이유]
VLM 호출은 장당 과금된다. 추출된 프레임 전부를 설명하면 장수가 늘어날수록
비용과 실행 시간이 그대로 늘어나므로, 시간 흐름을 대표할 만큼만 골라 그
프레임에만 호출한다(records.sample_time_quantiles). 장면 선정을 관찰 결과가
나온 뒤에 하면(illustrate.select_key_scenes처럼) 이미 전부 VLM을 태운 뒤라
비용을 아낄 수 없으므로, 표본 추출은 반드시 Stage 1 이전, 파일 메타데이터만
가지고 이뤄진다.
"""

from __future__ import annotations

import argparse
import random
from pathlib import Path
from typing import Sequence

from .. import config
from .. import diagnostics
from .. import prompts as P
from ..console import info, step, warn
from ..gms import GMSAuthError, GMSError
from ..records import (
    UNKNOWN,
    RecordsError,
    WalkInfo,
    adaptive_sample_size,
    dump_records,
    iter_frames,
    load_records,
    outdoor,
    sample_time_quantiles,
    walk_duration,
    walk_time_range,
)
from ..stages import ComposeError, compose_walk_log, observe_frames, observe_outdoor_frames
from . import common

__all__ = ["build_parser", "main"]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="run_walk_log.py",
        description="산책 프레임에서 관찰 기록과 산책 일지를 만든다",
    )

    source = parser.add_argument_group("입력")
    source.add_argument("--frames", type=Path, default=config.DEFAULT_FRAME_DIR,
                        help=f"프레임 폴더 (기본: {config.DEFAULT_FRAME_DIR})")
    source.add_argument("--manifest", type=Path, default=None,
                        help="manifest.json 경로 "
                             "(기본: 프레임 폴더 안의 manifest.json 이 있으면 사용)")
    source.add_argument("--started-at", default=None,
                        help="산책 시작 시각 (ISO 8601, 예: 2026-07-28T08:12:03). "
                             "주면 프레임별 촬영 일시를 계산해 시간대 추정을 우회한다")
    source.add_argument("--location", default=UNKNOWN,
                        help="산책 위치 (예: OO천 산책로)")
    source.add_argument("--records", type=Path, default=None,
                        help="기존 관찰 기록을 읽는다 (--no-observe 와 함께)")
    source.add_argument("--limit", type=int, default=None,
                        help="앞에서 N장만 처리 (동작 확인용)")
    source.add_argument("--quarters", type=int, default=None,
                        help="표본 등분 수를 직접 지정. 생략하면 전체 프레임의 약 10%% "
                             "(최소 4, 최대 12)로 자동 계산")
    source.add_argument("--sample-ratio", type=float, default=None,
                        help="자동 계산 비율을 바꾼다 (기본 0.10)")
    source.add_argument("--no-sample", action="store_true",
                        help="표본 추출을 건너뛰고 추출된 프레임 전부를 처리한다")
    source.add_argument("--sample-seed", type=int, default=None,
                        help="표본 추출 난수 시드 (재현 가능한 결과가 필요할 때)")
    source.add_argument("--allow-indoor", action="store_true",
                        help="실내 프레임을 배제하지 않고 그대로 사용한다 "
                             "(실내 테스트 영상용)")

    stages = parser.add_argument_group("단계 선택")
    stages.add_argument("--no-observe", action="store_true",
                        help="Stage 1을 건너뛴다 (--records 필요)")
    stages.add_argument("--no-diary", action="store_true",
                        help="Stage 2를 건너뛴다 (관찰 기록만 만든다)")
    stages.add_argument("--style", default=P.DEFAULT_DIARY_STYLE,
                        choices=list(P.DIARY_STYLES), help="일지 문체 프리셋")
    stages.add_argument("--image-prompt", action="store_true",
                        help="삽화용 이미지 프롬프트도 만들어 출력 "
                             "(그림은 만들지 않는다)")
    stages.add_argument("--image-style", default=P.DEFAULT_IMAGE_STYLE,
                        choices=list(P.IMAGE_STYLES))
    stages.add_argument("--story-image", action="store_true",
                        help="일지(이야기)를 바탕으로 감성 이미지 한 장을 생성")
    stages.add_argument("--verify-image", action="store_true",
                        help="감성 이미지가 여정을 반영했는지 VLM으로 검증하고, "
                             "불합격 시 최대 2회 재생성 (검증·재생성마다 API 비용 추가)")

    tuning = parser.add_argument_group("Stage 1 튜닝")
    tuning.add_argument("--no-thinking", action="store_true",
                        help="사고 토큰을 끈다 (thinking_budget=0). "
                             "--check 로 프록시 지원 여부를 먼저 확인하세요")
    tuning.add_argument("--temperature", type=float, default=None,
                        help=f"기본값 {P.FRAME_EXTRACT.temperature}. "
                             "올리면 없는 사물이 등장한다")
    tuning.add_argument("--max-attempts", type=int, default=3,
                        help="일시적 실패(429/5xx) 재시도 횟수")

    common.add_connection_args(parser)
    common.add_output_args(parser)
    common.add_upload_args(parser)
    parser.add_argument("--check", action="store_true",
                        help="프록시가 무엇을 지원하는지 확인하고 종료")
    return parser


def _frame_spec(args: argparse.Namespace) -> P.PromptSpec | None:
    """Stage 1 스펙을 인자에 맞게 조정한다. 조정할 게 없으면 None."""
    overrides: dict = {}
    if args.no_thinking:
        overrides["thinking_budget"] = 0
    if args.temperature is not None:
        overrides["temperature"] = args.temperature
    return P.FRAME_EXTRACT.tweak(**overrides) if overrides else None


def _resolve_manifest(args: argparse.Namespace) -> Path | None:
    if args.manifest is not None:
        return args.manifest
    candidate = Path(args.frames) / "manifest.json"
    return candidate if candidate.is_file() else None


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    if args.check:
        results = diagnostics.report()
        return common.EXIT_OK if all(r.status != "inconclusive" for r in results) \
            else common.EXIT_ERROR

    if args.no_observe and args.records is None:
        warn("--no-observe 는 --records 와 함께 써야 합니다")
        return common.EXIT_ERROR

    run_dir = common.resolve_run_dir(args)
    walk = WalkInfo(date=args.date or UNKNOWN, started_at=args.started_at,
                    location=args.location)

    try:
        client = common.build_client(args, run_dir)
    except config.ConfigError as exc:
        warn(str(exc))
        return common.EXIT_ERROR

    records_path = run_dir / config.RECORDS_NAME
    paths: dict[str, Path] = {}

    try:
        # ---------------------------------------------- Stage 1
        if args.no_observe:
            records, loaded_walk = load_records(args.records, frame_dir=args.frames)
            step(f"기존 관찰 기록 {len(records)}개를 읽었습니다: {args.records}")
            if walk.started_at is None and loaded_walk.started_at:
                walk = loaded_walk
        else:
            full_metas = iter_frames(args.frames, manifest=_resolve_manifest(args),
                                     walk=walk)
            metas = full_metas
            if not args.no_sample:
                before = len(metas)
                if args.quarters is not None:
                    n = args.quarters
                    how = f"{n}등분 (직접 지정)"
                else:
                    n = adaptive_sample_size(
                        before,
                        ratio=args.sample_ratio or config.SAMPLE_RATIO)
                    how = (f"{n}등분 (전체 {before}장의 "
                           f"약 {int((args.sample_ratio or config.SAMPLE_RATIO)*100)}%,"
                           f" {config.SAMPLE_MIN}~{config.SAMPLE_MAX} 범위)")
                rng = random.Random(args.sample_seed) \
                    if args.sample_seed is not None else None
                metas = sample_time_quantiles(metas, n, rng=rng)
                step(f"[표본 추출] {before}개 -> {len(metas)}개 ({how}, "
                     f"구간 중앙 밴드)")
            if args.limit:
                metas = metas[:args.limit]
            step(f"[Stage 1] 프레임 {len(metas)}개 -> 관찰 기록")

            if args.allow_indoor:
                records, failures = observe_frames(
                    client, metas, spec=_frame_spec(args),
                    max_attempts=args.max_attempts,
                )
            else:
                records = observe_outdoor_frames(
                    client, metas, full_metas, spec=_frame_spec(args),
                    max_attempts=args.max_attempts,
                )
                failures = []
            common.report_failures(failures)
            if not records:
                warn("모든 프레임 처리에 실패했습니다")
                return common.EXIT_ERROR

            # frame_records.json에는 실내 판정본도 그대로 남긴다(감사 가능성).
            # 다운스트림(일지/이미지) 재료로는 아래에서 outdoor()로만 거른다.
            dump_records(records, records_path, walk=walk,
                         prompt_version=P.PROMPT_VERSION)
            paths["관찰 기록"] = records_path

        if args.allow_indoor:
            content_records = records
        else:
            content_records = outdoor(records)
            if not content_records:
                warn("야외 기록이 없어(전부 실내) 실내 기록을 포함해 진행합니다.")
                content_records = records

        # ---------------------------------------------- Stage 2
        # 일지 본문은 content_records(실내 배제 후)를 재료로 쓴다. 소요시간은
        # 실제 산책 전체를 반영해야 하므로 records(실내 포함) 기준을 유지한다.
        if not args.no_diary:
            diary = compose_walk_log(
                client, content_records,
                walk_date=args.date or (walk.date if walk.date != UNKNOWN else None),
                duration=walk_duration(records),
                style=args.style,
            )
            time_range = walk_time_range(walk, records)
            if time_range:
                diary = diary.rstrip() + f"\n- 시간: {time_range[0]} ~ {time_range[1]}\n"
            diary_path = run_dir / config.DIARY_NAME
            diary_path.write_text(diary, encoding="utf-8")
            paths["산책 일지"] = diary_path

            info("")
            info("=" * 50)
            info(diary)

        # ---------------------------------------------- Stage 3 (감성 이미지)
        if args.story_image:
            if args.no_diary:
                warn("--story-image 는 일지가 필요합니다 (--no-diary 와 함께 쓸 수 없음)")
                return common.EXIT_ERROR
            from ..stages.illustrate import IllustrateError, build_story_image
            try:
                image_path = build_story_image(
                    client, content_records, diary,
                    run_dir / config.STORY_IMAGE_NAME,
                    style=args.image_style,
                    verify=args.verify_image,
                )
                paths["감성 이미지"] = image_path
            except IllustrateError as exc:
                warn(str(exc))
                return common.EXIT_ERROR

        # ---------------------------------------------- Stage 3B (프롬프트만)
        if args.image_prompt:
            from ..stages.illustrate import select_key_scenes, write_scene_prompt

            scenes = select_key_scenes(content_records, 1)
            prompt = write_scene_prompt(client, scenes[0], position=1, total=1,
                                        style=args.image_style)
            info("")
            info("=" * 50)
            info("[image prompt]")
            info(prompt)

    except (RecordsError, ComposeError) as exc:
        warn(str(exc))
        return common.EXIT_ERROR
    except GMSAuthError as exc:
        warn(str(exc))
        return common.EXIT_ERROR
    except GMSError as exc:
        warn(f"API 호출 실패: {exc}")
        return common.EXIT_ERROR
    finally:
        common.report_tokens(client)
        client.close()

    if args.dump_payload:
        paths["요청 덤프"] = run_dir / config.PAYLOAD_DIRNAME
    common.print_paths(paths)
    common.upload_if_requested(args, run_dir)
    return common.EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())