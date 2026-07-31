"""산책 흐름 삽화 생성 CLI.

  Stage A  관찰 기록 -> 장면 전환 감지 -> 대표 프레임 N장  (로컬, API 없음)
  Stage B  각 장면 -> 영어 이미지 프롬프트                  (LLM)
  Stage C  각 장면 -> 삽화                                  (이미지 모델)
  Stage D  삽화들 -> 스토리보드 한 장                        (로컬, Pillow)

사용:
    python run_flow_image.py --dry-run                 # API 없이 장면 선정만
    python run_flow_image.py -n 5 --style watercolor
    python run_flow_image.py --mode single             # 한 장으로 요약
    python run_flow_image.py --no-ref --layout grid

[분할 전에서 바뀐 점]
1. 기록 형식을 추측하지 않는다. records.load_records 가 형식을 소유한다.
2. sys.exit 대신 종료 코드를 반환한다.
3. 기본 기록 경로가 outputs/<날짜>/frame_records.json 이다.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Sequence

from .. import config
from .. import prompts as P
from ..console import info, step, warn
from ..gms import GMSAuthError, GMSError
from ..records import UNKNOWN, RecordsError, load_records, usable, walk_duration
from ..stages import IllustrateError, build_single_image, build_storyboard
from ..stages.illustrate import select_key_scenes
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
    shape.add_argument("--mode", choices=("storyboard", "single"),
                       default="storyboard",
                       help="storyboard: 칸 여러 개 / single: 전체를 한 장으로")
    shape.add_argument("--layout", choices=("row", "grid"), default="row")
    shape.add_argument("--style", default=P.DEFAULT_IMAGE_STYLE,
                       choices=list(P.IMAGE_STYLES))
    shape.add_argument("--no-ref", action="store_true",
                       help="실제 프레임을 참조하지 않고 텍스트만으로 생성")
    shape.add_argument("--no-caption-llm", action="store_true",
                       help="캡션을 LLM 대신 location_type 으로 채운다")
    shape.add_argument("--font", default=None,
                       help=f"한국어 TTF 경로 (환경변수 {config.FONT_ENV} 도 가능)")
    shape.add_argument("-o", "--out", type=Path, default=None,
                       help=f"기본: <출력폴더>/{config.FLOW_IMAGE_NAME}")
    shape.add_argument("--dry-run", action="store_true",
                       help="API 호출 없이 장면 선정 결과만 출력")

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


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    run_dir = common.resolve_run_dir(args, create=not args.dry_run)
    records_path = args.records or (run_dir / config.RECORDS_NAME)
    out_path = args.out or (run_dir / config.FLOW_IMAGE_NAME)

    try:
        records, walk = load_records(records_path, frame_dir=args.frames)
    except RecordsError as exc:
        warn(str(exc))
        step("먼저 run_walk_log.py 로 관찰 기록을 만들거나 "
             "--records 로 경로를 지정하세요.")
        return common.EXIT_ERROR

    step(f"관찰 기록 {len(records)}개를 읽었습니다: {records_path}")
    walk_date = args.date or walk.date

    if args.dry_run:
        try:
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