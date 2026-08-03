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
    "run_label",
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
                       help=f"기본값: {config.OUTPUTS_DIR / '<오늘 날짜>' / 'session<N>'} "
                            "(주면 세션 자동 계산을 건너뛰고 이 폴더를 그대로 쓴다)")
    group.add_argument("--date", default=None,
                       help="산책 날짜 (YYYY-MM-DD). 출력 폴더 이름으로도 쓰인다")
    group.add_argument("--session", type=int, default=None,
                       help="세션 번호를 직접 지정한다 (기본: 자동 계산)")


def add_upload_args(parser: argparse.ArgumentParser) -> None:
    group = parser.add_argument_group("업로드")
    group.add_argument("--upload-s3", dest="upload_s3", action="store_true",
                       default=True,
                       help=f"일지+감성 이미지({', '.join(config.S3_UPLOAD_FILES)})만 S3에 "
                            f"업로드한다 (기본값, 버킷: {config.S3_BUCKET})")
    group.add_argument("--no-upload-s3", dest="upload_s3", action="store_false",
                       help="S3 업로드를 건너뛴다 (로컬 저장만)")
    group.add_argument("--s3-bucket", default=config.S3_BUCKET,
                       help="기본값은 config.S3_BUCKET (환경변수 S3_BUCKET으로도 설정 가능)")
    group.add_argument("--s3-prefix", default=config.S3_PREFIX,
                       help="기본값은 config.S3_PREFIX (환경변수 S3_PREFIX으로도 설정 가능)")


def resolve_run_dir(
    args: argparse.Namespace, *, create: bool = True, new_session: bool = True,
) -> Path:
    """이번 실행이 쓸 세션 폴더를 정한다.

    new_session=True (run_walk_log.py 기본): 그날 가장 큰 세션 번호 + 1을 새로
      만든다. 하루에 산책을 여러 번 다녀오면 실행마다 새 세션이 생겨서
      이전 산책 기록을 덮어쓰지 않는다.
    new_session=False (run_flow_image.py): 그날 가장 최근 세션을 그대로 쓴다.
      삽화 생성은 이미 있는 관찰 기록을 읽기만 하는 단계라, 여기서 새 세션을
      만들면 방금 만든 관찰 기록과 다른 빈 폴더를 보게 된다.

    --out-dir 를 주면 이 계산을 전부 건너뛰고 그 폴더를 그대로 쓴다.
    --session 을 주면 자동 계산 대신 그 번호를 쓴다(특정 세션을 다시 쓰고 싶을 때).
    """
    if args.out_dir is not None:
        path = Path(args.out_dir)
        if create:
            path.mkdir(parents=True, exist_ok=True)
        return path

    day = getattr(args, "date", None)
    session = getattr(args, "session", None)
    if session is None:
        existing = config.list_sessions(day)
        if existing:
            session = existing[-1] + 1 if new_session else existing[-1]
        else:
            session = 1

    return config.run_dir(day, session=session, create=create)


def run_label(run_dir: Path) -> str:
    """로그/업로드 메시지에 쓸 "<날짜>/session<N>" 형태 라벨.

    run_dir이 outputs/ 바깥(예: --out-dir로 임의 경로 지정)이면 폴더 이름만 쓴다.
    """
    try:
        return run_dir.relative_to(config.OUTPUTS_DIR).as_posix()
    except ValueError:
        return run_dir.name


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
    """run_dir 안의 AI 최종 결과물(config.S3_UPLOAD_FILES)만 S3에 올린다.

    기본 동작이며 --no-upload-s3로 끌 수 있다. 실패해도 프로세스를 죽이지
    않는다. 로컬 산출물은 이미 완성된 상태이므로, 업로드 실패로 이미 만든
    결과까지 EXIT_ERROR 처리할 이유가 없다(observe_frames가 프레임 하나의
    실패로 전체를 멈추지 않는 것과 같은 원칙).
    """
    if not getattr(args, "upload_s3", True):
        return

    from ..storage import S3UploadError, upload_outputs

    try:
        uploaded = upload_outputs(run_dir, bucket=args.s3_bucket, prefix=args.s3_prefix)
    except S3UploadError as exc:
        warn(f"S3 업로드 실패: {exc}")
        return

    if not uploaded:
        step("[S3 업로드] 올릴 파일이 없습니다 (일지/감성 이미지가 아직 없음)")
        return

    step(f"[S3 업로드] {len(uploaded)}개 파일 -> "
         f"s3://{args.s3_bucket}/{args.s3_prefix}/{run_label(run_dir)}/")