"""outputs/ 산출물을 S3에 업로드.

[이 파일의 역할]
run_walk_log.py / run_flow_image.py가 만든 outputs/<날짜>/ 아래 파일들
(관찰 기록, 일지, 삽화, 스토리보드)을 S3에 올린다.

[자격증명]
GMS_KEY와 달리 이 파일은 자격증명을 직접 읽지 않는다. boto3의 기본
자격증명 체인(환경변수 -> ~/.aws/credentials -> IAM 역할)에 맡긴다.
버킷 이름/프리픽스/리전만 config.py가 소유한다.

[업로드 범위]
payload/ (요청 덤프, --dump-payload로 생성) 는 내부 디버깅용이라 제외한다.
그 외 run_dir 아래 파일은 전부 올린다.
"""

from __future__ import annotations

from pathlib import Path

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

# 이 이름의 하위 폴더는 업로드하지 않는다.
_EXCLUDED_DIRNAMES = {config.PAYLOAD_DIRNAME}


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
) -> dict[str, str]:
    """run_dir(outputs/<날짜>) 아래 파일을 전부 올리고 {상대경로: s3 URI}를 반환한다.

    키는 <prefix>/<run_dir 이름>/<run_dir 기준 상대경로> 형태다.
    예: outputs/2026-07-31/walk_flow.png
        -> s3://<bucket>/robot-images/outputs/2026-07-31/walk_flow.png
    """
    run_dir = Path(run_dir)
    if not run_dir.is_dir():
        raise S3UploadError(f"업로드할 폴더가 없습니다: {run_dir}")

    uploaded: dict[str, str] = {}
    for path in sorted(run_dir.rglob("*")):
        if not path.is_file():
            continue
        rel_parts = path.relative_to(run_dir).parts
        if _EXCLUDED_DIRNAMES & set(rel_parts[:-1]):
            continue
        rel = "/".join(rel_parts)
        key = f"{prefix}/{run_dir.name}/{rel}" if prefix else f"{run_dir.name}/{rel}"
        uploaded[rel] = upload_file(path, key, bucket=bucket)
    return uploaded
