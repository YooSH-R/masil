"""outputs/ 산출물을 S3에 업로드.

[이 파일의 역할]
run_walk_log.py / run_flow_image.py가 만든 outputs/<날짜>/session<N>/ 를
통째로 S3에 미러링한다. 하위 디렉토리(flow_panels/ 등)도 상대 경로를
유지한 채 그대로 올라간다.

[왜 제외 목록으로 바뀌었는가]
예전에는 "AI 최종 결과물"만 고른 허용 목록(S3_UPLOAD_FILES) 방식이었다.
그러면 새 산출물(flow_panels/, image_manifest.json 등)이 생길 때마다
목록에 추가하지 않는 한 조용히 안 올라갔다 - 실제로 flow_panels/를
깜빡해 스토리보드 패널이 한 번도 업로드되지 않은 채로 몇 주가 지났다.
지금은 반대로 config.S3_UPLOAD_EXCLUDE_DIRS(payload/ 하나뿐)만 빼고
세션 폴더 전체를 올린다 - 새 파일이 늘어도 기본적으로 새지 않는다.

[자격증명]
GMS_KEY와 달리 이 파일은 자격증명을 직접 읽지 않는다. boto3의 기본
자격증명 체인(환경변수 -> ~/.aws/credentials -> IAM 역할)에 맡긴다.
버킷 이름/프리픽스/리전만 config.py가 소유한다.
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence

from . import config

__all__ = ["S3UploadError", "upload_file", "upload_outputs"]


class S3UploadError(RuntimeError):
    """S3 업로드 실패. 자격증명/권한/네트워크 문제를 사용자에게 그대로 보여준다."""


CONTENT_TYPES = {
    ".json": "application/json",
    ".md": "text/markdown; charset=utf-8",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
}


def _run_key_prefix(run_dir: Path) -> str:
    """S3 키에 쓸 "<날짜>/session<N>" 조각.

    run_dir은 이제 outputs/<날짜>/session<N> 형태라 run_dir.name만 쓰면
    "session2"만 남고 날짜가 사라진다(--out-dir로 outputs/ 바깥 임의 경로를
    줬을 때는 이 상대경로 계산이 안 통하므로 폴더 이름으로 물러난다).
    """
    try:
        return run_dir.relative_to(config.OUTPUTS_DIR).as_posix()
    except ValueError:
        return run_dir.name


def _client():
    try:
        import boto3
    except ImportError as exc:
        raise S3UploadError(
            "boto3가 설치되어 있지 않습니다. `pip install boto3` 로 설치하세요."
        ) from exc
    return boto3.client("s3", region_name=config.AWS_REGION)


def upload_file(path: str | Path, key: str, *, bucket: str = config.S3_BUCKET) -> str:
    """파일 하나를 지정한 키로 업로드하고 s3:// URI를 반환한다."""
    try:
        from botocore.exceptions import BotoCoreError, ClientError, NoCredentialsError
    except ImportError as exc:
        raise S3UploadError(
            "boto3가 설치되어 있지 않습니다. `pip install boto3` 로 설치하세요."
        ) from exc

    path = Path(path)
    content_type = CONTENT_TYPES.get(path.suffix.lower())
    extra_args = {"ContentType": content_type} if content_type else {}

    try:
        _client().upload_file(str(path), bucket, key, ExtraArgs=extra_args)
    except NoCredentialsError as exc:
        raise S3UploadError(
            "AWS 자격증명을 찾을 수 없습니다. AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY "
            "환경변수나 ~/.aws/credentials 를 설정하세요."
        ) from exc
    except (BotoCoreError, ClientError) as exc:
        raise S3UploadError(f"{path.name} 업로드 실패 (s3://{bucket}/{key}): {exc}") from exc
    return f"s3://{bucket}/{key}"


def upload_outputs(
    run_dir: str | Path,
    *,
    bucket: str = config.S3_BUCKET,
    prefix: str = config.S3_PREFIX,
    exclude_dirs: Sequence[str] = config.S3_UPLOAD_EXCLUDE_DIRS,
) -> dict[str, str]:
    """run_dir(outputs/<날짜>/session<N>) 전체를 재귀적으로 미러링해 올리고
    {run_dir 기준 상대 경로: s3 URI}를 반환한다.

    exclude_dirs에 속한 최상위 하위 디렉토리(기본: payload/)는 통째로
    건너뛴다. 그 외 하위 디렉토리(flow_panels/ 등)는 상대 경로를 유지한
    채 그대로 올라간다 (예: flow_panels/event_01.png).

    파일이 하나도 없으면(예: --no-diary로 아직 아무것도 안 만든 경우)
    빈 dict를 반환한다 - 부분 완료도 정상 상태다.

    키는 <prefix>/<날짜>/session<N>/<상대경로> 형태다.
    예: outputs/2026-07-31/session2/flow_panels/event_01.png
        -> s3://<bucket>/robot-images/device-001/2026-07-31/session2/flow_panels/event_01.png
    """
    run_dir = Path(run_dir)
    if not run_dir.is_dir():
        raise S3UploadError(f"업로드할 폴더가 없습니다: {run_dir}")

    run_key = _run_key_prefix(run_dir)
    excluded = set(exclude_dirs)
    uploaded: dict[str, str] = {}
    for path in sorted(run_dir.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(run_dir)
        if rel.parts and rel.parts[0] in excluded:
            continue
        rel_key = rel.as_posix()
        key = f"{prefix}/{run_key}/{rel_key}" if prefix else f"{run_key}/{rel_key}"
        uploaded[rel_key] = upload_file(path, key, bucket=bucket)
    return uploaded
