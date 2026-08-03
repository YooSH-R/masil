"""run.py - 전체 파이프라인: 관찰 -> 이야기 -> 감성 이미지 -> (선택) 스토리보드.

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


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="run.py", description="산책 일지 전체 파이프라인")
    parser.add_argument("--frames", default=None)
    parser.add_argument("--diary-style", default="story", help="일지 문체")
    parser.add_argument("--image-style", default="watercolor", help="이미지 스타일")
    parser.add_argument("--quarters", type=int, default=4)
    parser.add_argument("--storyboard", action="store_true",
                        help="감성 이미지에 더해 스토리보드도 생성")
    parser.add_argument("--upload-s3", dest="upload_s3", action="store_true",
                        default=True, help="완성된 세션 폴더를 S3에 업로드한다 (기본값)")
    parser.add_argument("--no-upload-s3", dest="upload_s3", action="store_false",
                        help="S3 업로드를 건너뛴다 (로컬 저장만)")
    parser.add_argument("--s3-bucket", default=None,
                        help="생략하면 하위 CLI의 기본값(config.S3_BUCKET)을 그대로 쓴다")
    parser.add_argument("--s3-prefix", default=None,
                        help="생략하면 하위 CLI의 기본값(config.S3_PREFIX)을 그대로 쓴다")
    args = parser.parse_args(argv)

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

    # 1단계: 관찰 + 이야기 + 감성 이미지
    log_argv = ["--style", args.diary_style,
                "--image-style", args.image_style,
                "--story-image",
                "--quarters", str(args.quarters)]
    if args.frames:
        log_argv += ["--frames", args.frames]
    # storyboard 단계가 없으면 이 단계가 파이프라인의 마지막이라 여기서 올린다.
    # storyboard 단계가 있으면 거기서 세션 폴더 전체를 한 번에 올리므로 여기선 끈다
    # (그렇지 않으면 일지/감성 이미지가 두 번 업로드된다).
    log_argv += s3_argv(upload=args.upload_s3 and not args.storyboard)
    code = walk_log.main(log_argv)
    if code != 0:
        return code          # 앞 단계 실패 시 뒤를 돌리지 않는다

    # 2단계(선택): 스토리보드. flow_image는 최근 세션의 기록을 자동으로 읽는다.
    if args.storyboard:
        flow_argv = ["--style", args.image_style]
        flow_argv += s3_argv(upload=args.upload_s3)
        return flow_image.main(flow_argv)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())