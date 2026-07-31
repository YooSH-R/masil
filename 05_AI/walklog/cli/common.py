"""두 CLI가 공유하는 인자와 헬퍼.

cli/walk_log.py 와 cli/flow_image.py 가 접속 설정·출력 폴더·오류 처리를
똑같이 반복하지 않게 한다.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Sequence

from .. import config
from ..console import info, step, warn
from ..gms import GMSClient

__all__ = [
    "add_connection_args",
    "add_output_args",
    "add_upload_args",
    "build_client",
    "resolve_run_dir",
    "report_failures",
    "report_tokens",
    "upload_if_requested",
    "EXIT_OK",
    "EXIT_ERROR",
]

EXIT_OK = 0
EXIT_ERROR = 1


def add_connection_args(parser: argparse.ArgumentParser) -> None:
    group = parser.add_argument_group("접속 / 프록시 호환")
    group.add_argument("--system-mode", choices=list(config.SYSTEM_MODES),
                       default=config.SYSTEM_MODE,
                       help="프록시가 systemInstruction을 무시하면 merge "
                            "(--check 로 확인)")
    group.add_argument("--no-schema", action="store_true",
                       help="responseSchema를 쓰지 않는다 (프록시가 거부할 때)")
    group.add_argument("--text-model", default=config.TEXT_MODEL)
    group.add_argument("--image-model", default=config.IMAGE_MODEL)
    group.add_argument("--dump-payload", action="store_true",
                       help="실제로 보낸 요청을 <출력폴더>/payload/ 에 저장 "
                            "(이미지는 지문으로 치환)")


def add_output_args(parser: argparse.ArgumentParser) -> None:
    group = parser.add_argument_group("출력")
    group.add_argument("--out-dir", type=Path, default=None,
                       help=f"기본값: {config.OUTPUTS_DIR / '<오늘 날짜>'}")
    group.add_argument("--date", default=None,
                       help="산책 날짜 (YYYY-MM-DD). 출력 폴더 이름으로도 쓰인다")


def add_upload_args(parser: argparse.ArgumentParser) -> None:
    group = parser.add_argument_group("업로드")
    group.add_argument("--upload-s3", action="store_true",
                       help=f"결과 파일을 S3에 업로드한다 (버킷: {config.S3_BUCKET})")
    group.add_argument("--s3-bucket", default=config.S3_BUCKET,
                       help="기본값은 config.S3_BUCKET (환경변수 S3_BUCKET으로도 설정 가능)")
    group.add_argument("--s3-prefix", default=config.S3_PREFIX,
                       help="기본값은 config.S3_PREFIX (환경변수 S3_PREFIX으로도 설정 가능)")


def resolve_run_dir(args: argparse.Namespace, *, create: bool = True) -> Path:
    if args.out_dir is not None:
        path = Path(args.out_dir)
        if create:
            path.mkdir(parents=True, exist_ok=True)
        return path
    return config.run_dir(getattr(args, "date", None), create=create)


def build_client(args: argparse.Namespace, run_dir: Path) -> GMSClient:
    """CLI 인자로부터 클라이언트를 만든다.

    테스트는 이 함수를 몽키패치해 가짜 클라이언트를 꽂는다.
    """
    return GMSClient(
        text_model=args.text_model,
        image_model=args.image_model,
        system_mode=args.system_mode,
        use_schema=not args.no_schema,
        dump_dir=(run_dir / config.PAYLOAD_DIRNAME) if args.dump_payload else None,
    )


def report_failures(failures: Sequence) -> None:
    if not failures:
        return
    warn(f"처리하지 못한 프레임 {len(failures)}개:")
    for failure in failures:
        step(f"  - {failure}")


def report_tokens(client: GMSClient) -> None:
    total = getattr(client, "total_tokens", 0)
    if total:
        step(f"[토큰 합계] {total:,}")


def print_paths(paths: dict[str, Path]) -> None:
    info("")
    for label, path in paths.items():
        info(f"{label}: {path}")


def upload_if_requested(args: argparse.Namespace, run_dir: Path) -> None:
    """--upload-s3 였으면 run_dir 전체를 S3에 올린다.

    실패해도 프로세스를 죽이지 않는다. 로컬 산출물은 이미 완성된 상태이므로,
    업로드 실패로 이미 만든 결과까지 EXIT_ERROR 처리할 이유가 없다
    (observe_frames가 프레임 하나의 실패로 전체를 멈추지 않는 것과 같은 원칙).
    """
    if not getattr(args, "upload_s3", False):
        return

    from ..storage import S3UploadError, upload_outputs

    try:
        uploaded = upload_outputs(run_dir, bucket=args.s3_bucket, prefix=args.s3_prefix)
    except S3UploadError as exc:
        warn(f"S3 업로드 실패: {exc}")
        return

    step(f"[S3 업로드] {len(uploaded)}개 파일 -> "
         f"s3://{args.s3_bucket}/{args.s3_prefix}/{run_dir.name}/")