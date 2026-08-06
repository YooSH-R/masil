"""run.py - 전체 파이프라인: 관찰 -> 이야기 -> 산책일지 이미지(journal, 기본) / (선택) 스토리보드.
감성 이미지(story_image.png)는 opt-in이다.

산책일지(walk_journal.png, 이벤트 삽화 보드)가 이 파이프라인의 기본 최종
산출물이다. --no-journal로만 끌 수 있다(API 비용 절감 등). AI가 생성하는
이미지는 저널의 이벤트 패널(flow_panels/)로 일원화됐고, walk_journal.png는
그 패널들의 로컬(Pillow) 합성본이다. 감성 이미지(story_image.png)는
별도 산출물이 필요할 때만 --story-image로 켠다.

[S3 업로드]
--upload-s3 는 이 스크립트 자체가 아니라 walk_log.main()/flow_image.main()에
전달되는 하위 CLI 옵션이다(cli/common.add_upload_args). 그 CLI들은 이제
기본값이 "업로드함"이므로, 여기서 업로드를 원치 않는 단계에는 플래그를
"생략"하는 게 아니라 --no-upload-s3 를 명시적으로 넘겨야 한다. 생략하면
하위 CLI 자신의 기본값(업로드함)이 그대로 적용되어 두 단계 모두 올라간다.
"""

from __future__ import annotations

import argparse
import sys

from walklog.cli import flow_image, walk_log
from walklog.console import step


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="run.py", description="산책 일지 전체 파이프라인")
    parser.add_argument("--frames", default=None)
    parser.add_argument("--diary-style", default="story", help="일지 문체")
    parser.add_argument("--image-style", default="watercolor", help="이미지 스타일")
    parser.add_argument("--quarters", type=int, default=None,
                        help="표본 등분 수를 직접 지정. 생략하면 walk_log.py가 "
                             "전체 프레임의 약 10%%(최소 4, 최대 12)로 자동 계산한다")
    parser.add_argument("--storyboard", action="store_true",
                        help="감성 이미지에 더해 스토리보드도 생성")
    parser.add_argument("--journal", dest="journal", action="store_true",
                        default=True,
                        help="이벤트 삽화 보드 형태의 산책일지 이미지"
                             "(walk_journal.png)를 생성한다 (기본값)")
    parser.add_argument("--no-journal", dest="journal", action="store_false",
                        help="산책일지 이미지 생성을 건너뛴다 (API 비용 절감)")
    parser.add_argument("--story-image", dest="story_image", action="store_true",
                        default=False,
                        help="이야기 기반 감성 이미지(story_image.png)도 생성한다 "
                             "(opt-in, API 비용 추가). 기본 파이프라인 산출물은 "
                             "저널(flow_panels/ + walk_journal.png)뿐이다")
    parser.add_argument("--verify-image", dest="verify_image", action="store_true",
                        default=True,
                        help="감성 이미지가 여정을 반영했는지 검증 후 필요시 재생성 "
                             "(--story-image일 때만 적용, 기본값)")
    parser.add_argument("--no-verify-image", dest="verify_image", action="store_false",
                        help="이미지 검증·재생성을 건너뛴다 (API 비용 절감)")
    parser.add_argument("--upload-s3", dest="upload_s3", action="store_true",
                        default=True, help="완성된 세션 폴더를 S3에 업로드한다 (기본값)")
    parser.add_argument("--no-upload-s3", dest="upload_s3", action="store_false",
                        help="S3 업로드를 건너뛴다 (로컬 저장만)")
    parser.add_argument("--s3-bucket", default=None,
                        help="생략하면 하위 CLI의 기본값(config.S3_BUCKET)을 그대로 쓴다")
    parser.add_argument("--s3-prefix", default=None,
                        help="생략하면 하위 CLI의 기본값(config.S3_PREFIX)을 그대로 쓴다")
    parser.add_argument("--started-at", default=None,
                        help="산책 시작 시각 (ISO 8601, 예: 2026-08-04T19:00:00). "
                             "일지의 시각 기록과 시간대 추정 우회에 쓰인다")
    parser.add_argument("--location", default=None,
                        help="산책 위치 (예: OO천 산책로)")

    args = parser.parse_args(argv)

    # 실행이 끝난 뒤에야 "저널이 안 나왔다"를 알아채는 대신, 시작 시점에
    # 이번 실행이 만들 산출물을 미리 보여준다 - 플래그 하나 빠뜨린 실수를
    # 결과물을 뒤지기 전에 알 수 있게.
    outputs_plan = ["관찰 기록", "산책 일지(md)"]
    if args.story_image:
        outputs_plan.append("감성 이미지")
    if args.storyboard:
        outputs_plan.append("스토리보드")
    if args.journal:
        outputs_plan.append("산책일지 이미지(journal)")
    step(f"[계획] 이번 실행 산출물: {', '.join(outputs_plan)}")

    def s3_argv(*, upload: bool) -> list[str]:
        """이번 단계에 대한 업로드 여부를 하위 CLI에 명시적으로 지시한다.

        생략하는 방식은 더 이상 안전하지 않다 - 하위 CLI의 기본값이 True라
        아무것도 안 넘기면 "업로드함"으로 해석되기 때문이다.
        """
        if not upload:
            return ["--no-upload-s3"]
        flags = ["--upload-s3"]
        if args.s3_bucket:
            flags += ["--s3-bucket", args.s3_bucket]
        if args.s3_prefix:
            flags += ["--s3-prefix", args.s3_prefix]
        return flags

    # 1단계: 관찰 + 이야기 + (opt-in) 감성 이미지
    log_argv = ["--style", args.diary_style,
                "--image-style", args.image_style]
    if args.quarters is not None:
        log_argv += ["--quarters", str(args.quarters)]
    if args.story_image:
        log_argv += ["--story-image"]
        if args.verify_image:
            log_argv += ["--verify-image"]
    if args.frames:
        log_argv += ["--frames", args.frames]
    if args.started_at:
        log_argv += ["--started-at", args.started_at]
    if args.location:
        log_argv += ["--location", args.location]
    # 2단계(스토리보드/저널)가 하나라도 있으면 이 단계는 마지막이 아니므로 업로드를
    # 끈다. 없으면 이 단계가 파이프라인의 마지막이라 여기서 올린다.
    # (그렇지 않으면 일지/감성 이미지가 여러 번 업로드된다)
    has_stage2 = args.storyboard or args.journal
    log_argv += s3_argv(upload=args.upload_s3 and not has_stage2)
    code = walk_log.main(log_argv)
    if code != 0:
        return code          # 앞 단계 실패 시 뒤를 돌리지 않는다

    # 2단계(선택): 스토리보드 / 저널. flow_image는 최근 세션의 기록을 자동으로
    # 읽으므로, 둘 다 요청되면 같은 세션에 순서대로 만들어도 안전하다.
    # 마지막 산출물을 만드는 호출에서만 세션 폴더 전체를 업로드한다.
    stage2: list[list[str]] = []
    if args.storyboard:
        stage2.append(["--style", args.image_style])
    if args.journal:
        stage2.append(["--mode", "journal", "--style", args.image_style])

    for index, flow_argv in enumerate(stage2):
        is_last = index == len(stage2) - 1
        code = flow_image.main(flow_argv + s3_argv(upload=args.upload_s3 and is_last))
        if code != 0:
            return code      # 앞 산출물 실패 시 뒤를 돌리지 않는다
    return 0


if __name__ == "__main__":
    raise SystemExit(main())