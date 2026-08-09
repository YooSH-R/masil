"""산책 흐름 삽화 생성 CLI.

  Stage A  관찰 기록 -> 장면 전환 감지 -> 대표 프레임 N장  (로컬, API 없음)
  Stage A' 관찰 기록 -> 이벤트 중요도 -> 대표 프레임 N장   (로컬, API 없음. --mode journal/panels)
  Stage B  각 장면 -> 영어 이미지 프롬프트                  (LLM)
  Stage C  각 장면 -> 삽화                                  (이미지 모델)
  Stage D  삽화들 -> 스토리보드 / 저널 한 장                 (로컬, Pillow. panels 모드는 없음)

기본 모드는 panels다: 이벤트 중요도 기준 삽화 패널 N장(세션 폴더에 바로
event_XX.png)만 만들고 보드로 합성하지 않는다. 보드가 필요하면 --mode journal을
쓴다(opt-in, run.py 기준으로는 --board). journal/storyboard 모드는 최종
합성본(walk_journal.png/walk_flow.png)과 개별 삽화가 섞이지 않도록 개별
삽화를 flow_panels/ 하위 폴더에 담는다 - panels 모드는 개별 삽화 자체가
유일한 산출물이라 그 구분이 필요 없다.

사용:
    python run_flow_image.py --dry-run                 # API 없이 이벤트 선정만 (기본: panels)
    python run_flow_image.py --events 5 --style watercolor
    python run_flow_image.py --mode storyboard -n 5     # 장면 전환 기준 스토리보드
    python run_flow_image.py --mode single             # 한 장으로 요약
    python run_flow_image.py --use-reference            # panels: 이벤트 프레임을 참조로 사용
    python run_flow_image.py --mode journal --events 5  # 저널: 이벤트 5개짜리 산책일지(보드)

[분할 전에서 바뀐 점]
1. 기록 형식을 추측하지 않는다. records.load_records 가 형식을 소유한다.
2. sys.exit 대신 종료 코드를 반환한다.
3. 기본 기록 경로가 outputs/<날짜>/session<N>/frame_records.json 이다.

[세션 폴더]
하루에 산책을 여러 번 다녀와 run_walk_log.py를 여러 번 돌리면
outputs/<날짜>/session1, session2, ... 로 나뉜다. 이 스크립트는 (--out-dir나
--session을 안 주면) 그중 가장 최근 세션을 읽는다 - 방금 만든 관찰 기록을
이어받아 삽화를 만드는 게 목적이라 새 세션을 만들면 안 되기 때문이다.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Sequence

from .. import config
from .. import prompts as P
from ..console import info, step, warn
from ..gms import GMSAuthError, GMSError
from ..records import (
    UNKNOWN,
    RecordsError,
    load_records,
    outdoor,
    usable,
    walk_duration,
    walk_time_range,
)
from ..stages import (
    IllustrateError,
    build_journal,
    build_panels,
    build_single_image,
    build_storyboard,
)
from ..stages.illustrate import _primary_subject, event_score, select_key_events, select_key_scenes
from . import common

__all__ = ["build_parser", "main"]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="run_flow_image.py",
        description="관찰 기록으로 산책 흐름 삽화를 만든다",
    )

    source = parser.add_argument_group("입력")
    source.add_argument("--records", type=Path, default=None,
                        help=f"관찰 기록 (기본: <출력폴더>/{config.RECORDS_NAME})")
    source.add_argument("--frames", type=Path, default=config.DEFAULT_FRAME_DIR,
                        help="참조 프레임 폴더")

    shape = parser.add_argument_group("생성 방식")
    shape.add_argument("-n", "--scenes", type=int, default=4, help="대표 장면 수")
    shape.add_argument("--events", type=int, default=4,
                       help="저널/패널(--mode journal/panels)에 실을 이벤트 수 (2~6 권장)")
    shape.add_argument("--mode", choices=("panels", "storyboard", "single", "journal"),
                       default="panels",
                       help="panels: 이벤트 중요도 기준 삽화 패널 N장을 세션 폴더에 "
                            "바로 저장, 보드 합성 없음 (기본값) / storyboard: 칸 여러 개 / "
                            "single: 전체를 한 장으로 / "
                            "journal: 이벤트 중요도 기준 스크랩북형 산책일지(보드, opt-in)")
    shape.add_argument("--layout", choices=("row", "grid"), default="row")
    shape.add_argument("--style", default=P.DEFAULT_IMAGE_STYLE,
                       choices=list(P.IMAGE_STYLES))
    shape.add_argument("--no-ref", action="store_true",
                       help="실제 프레임을 참조하지 않고 텍스트만으로 생성 "
                            "(storyboard/single/journal 전용. panels는 --use-reference 참고)")
    shape.add_argument("--use-reference", dest="use_reference", action="store_true",
                       default=False,
                       help="panels 전용: 이벤트의 실제 프레임을 참조로 사용한다 "
                            "(기본은 참조 없음 - 수채화에서는 화풍 불일치 위험이 있다. "
                            "2026-08-05 실측상 참조 포함 생성의 86%가 화풍 검사 불합격이었다). "
                            "photoreal 스타일은 이 플래그와 무관하게 항상 참조를 쓴다")
    shape.add_argument("--no-caption-llm", action="store_true",
                       help="캡션을 LLM 대신 location_type 으로 채운다 "
                            "(storyboard 전용. journal은 항상 LLM 캡션을 쓴다)")
    shape.add_argument("--verify-style", dest="verify_style", action="store_true",
                       default=True,
                       help="저널 패널마다 화풍(톤)이 일치하는지 검사 후 "
                            "필요시 재생성한다 (journal 전용, 기본값)")
    shape.add_argument("--no-verify-style", dest="verify_style", action="store_false",
                       help="저널 화풍 검사를 건너뛴다 (API 비용 절감)")
    shape.add_argument("--font", default=None,
                       help=f"한국어 TTF 경로 (환경변수 {config.FONT_ENV} 도 가능)")
    shape.add_argument("-o", "--out", type=Path, default=None,
                       help=f"기본: <출력폴더>/{config.FLOW_IMAGE_NAME} "
                            f"(journal 모드는 {config.JOURNAL_NAME})")
    shape.add_argument("--dry-run", action="store_true",
                       help="API 호출 없이 장면(또는 이벤트) 선정 결과만 출력")

    common.add_connection_args(parser)
    common.add_output_args(parser)
    common.add_upload_args(parser)
    return parser


def _print_dry_run(records, count: int) -> int:
    """API를 부르지 않고 어떤 장면이 뽑히는지만 보여준다."""
    scenes = select_key_scenes(records, count)
    info(f"\n선정된 장면 {len(scenes)}개 (전체 기록 {len(records)}개, "
         f"사용 가능 {len(usable(records))}개)")
    for position, scene in enumerate(scenes, 1):
        observation = scene.observation
        reference = scene.reference
        info(f"  {position}. [{scene.elapsed}] "
             f"{observation.get('location_type', '?')} / "
             f"{observation.get('weather', '?')} / "
             f"conf={scene.confidence_mean:.2f} / weight={scene.weight} / "
             f"참조={reference.name if reference else '없음'}")
        info(f"     objects={observation.get('objects') or []} "
             f"atmosphere={observation.get('atmosphere') or []}")
    return common.EXIT_OK


def _print_dry_run_events(records, count: int) -> int:
    """API를 부르지 않고 어떤 이벤트가 뽑히는지만 보여준다 (--mode journal)."""
    events = select_key_events(records, count)
    info(f"\n선정된 이벤트 {len(events)}개 (전체 기록 {len(records)}개, "
         f"사용 가능 {len(usable(records))}개)")
    for position, event in enumerate(events, 1):
        observation = event.observation
        reference = event.reference
        info(f"  {position}. [{event.elapsed}] score={event_score(event.record):.1f} / "
             f"피사체={_primary_subject(event.record) or '?'} / "
             f"conf={event.confidence_mean:.2f} / "
             f"참조={reference.name if reference else '없음'}")
        info(f"     animals={observation.get('animals') or []} "
             f"notable={observation.get('notable') or ''} "
             f"objects={observation.get('objects') or []}")
    return common.EXIT_OK


_SUMMARY_RE = re.compile(r"\*\*한 줄 요약\*\*:\s*(.+)")


def _diary_note(run_dir: Path) -> str:
    """세션 폴더의 walk_log.md에서 '한 줄 요약' 줄을 읽는다.

    없거나 파싱에 실패하면 빈 문자열이다. LLM을 추가로 부르지 않는다 -
    Stage 2가 이미 만든 값을 재활용할 뿐이다.
    """
    diary_path = run_dir / config.DIARY_NAME
    if not diary_path.is_file():
        return ""
    match = _SUMMARY_RE.search(diary_path.read_text(encoding="utf-8"))
    return match.group(1).strip() if match else ""


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    run_dir = common.resolve_run_dir(args, create=not args.dry_run, new_session=False)
    records_path = args.records or (run_dir / config.RECORDS_NAME)
    default_name = config.JOURNAL_NAME if args.mode == "journal" else config.FLOW_IMAGE_NAME
    out_path = args.out or (run_dir / default_name)

    try:
        records, walk = load_records(records_path, frame_dir=args.frames)
    except RecordsError as exc:
        warn(str(exc))
        step("먼저 run_walk_log.py 로 관찰 기록을 만들거나 "
             "--records 로 경로를 지정하세요.")
        return common.EXIT_ERROR

    step(f"관찰 기록 {len(records)}개를 읽었습니다: {records_path}")

    # walk_log.py --allow-indoor로 실내 기록을 남겨 뒀을 수 있으므로, 여기서도
    # 삽화 재료에서 한 번 더 거른다(이중 안전판). 전부 실내면 원본으로 폴백한다.
    outdoor_records = outdoor(records)
    if not outdoor_records:
        warn("야외 기록이 없어(전부 실내) 실내 기록을 포함해 진행합니다.")
    else:
        records = outdoor_records

    walk_date = args.date or walk.date

    if args.dry_run:
        try:
            if args.mode in ("journal", "panels"):
                return _print_dry_run_events(records, args.events)
            return _print_dry_run(records, args.scenes)
        except IllustrateError as exc:
            warn(str(exc))
            return common.EXIT_ERROR

    try:
        client = common.build_client(args, run_dir)
    except config.ConfigError as exc:
        warn(str(exc))
        return common.EXIT_ERROR

    paths: dict[str, Path] = {}
    try:
        if args.mode == "single":
            path = build_single_image(
                client, records, out_path,
                scene_count=args.scenes, style=args.style,
                walk_date=walk_date, duration=walk_duration(records),
                use_reference=not args.no_ref,
            )
            paths["삽화"] = path
        elif args.mode == "journal":
            panel_dir = run_dir / config.PANELS_DIRNAME
            path = build_journal(
                client, records, out_path,
                event_count=args.events, style=args.style,
                walk_date=walk_date, time_range=walk_time_range(walk, records),
                duration=walk_duration(records), note=_diary_note(run_dir),
                use_reference=not args.no_ref, verify_style=args.verify_style,
                panel_dir=panel_dir, font_path=args.font,
            )
            paths["산책일지"] = path
            paths["이벤트 삽화"] = panel_dir
        elif args.mode == "panels":
            panel_dir = run_dir
            # photoreal은 참조와 화풍이 싸우지 않으므로 --use-reference와 무관하게
            # 기존 동작(참조 사용)을 유지한다. 그 외 스타일은 기본이 참조 없음이다
            # (2026-08-05 실측: 참조 포함 수채화 생성의 86%가 화풍 검사 불합격).
            use_reference = True if args.style in P.PHOTO_STYLES else args.use_reference
            path = build_panels(
                client, records, panel_dir,
                event_count=args.events, style=args.style,
                use_reference=use_reference, verify_style=args.verify_style,
            )
            paths["이벤트 패널"] = path
        else:
            panel_dir = run_dir / config.PANELS_DIRNAME
            path, scenes = build_storyboard(
                client, records, out_path,
                scene_count=args.scenes, style=args.style, layout=args.layout,
                walk_date=walk_date, use_reference=not args.no_ref,
                use_caption_llm=not args.no_caption_llm,
                panel_dir=panel_dir, font_path=args.font,
            )
            paths["스토리보드"] = path
            paths["개별 삽화"] = panel_dir

            captions = ", ".join(
                f"{i}.{s.record.caption or s.caption}"
                for i, s in enumerate(scenes, 1)
            )
            step(f"칸 캡션: {captions}")

    except IllustrateError as exc:
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