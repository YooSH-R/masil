"""storage.py 검증. 실제 AWS 대신 가짜 S3 클라이언트를 꽂는다."""

from __future__ import annotations

import pytest

from walklog import storage
from walklog.storage import S3UploadError, upload_file, upload_outputs


class FakeS3Client:
    """upload_file 호출을 기록한다. raise_on으로 특정 키에서 실패를 흉내낸다."""

    def __init__(self, raise_on: set[str] | None = None):
        self.calls: list[tuple[str, str, str, dict]] = []
        self._raise_on = raise_on or set()

    def upload_file(self, filename, bucket, key, ExtraArgs=None):
        if key in self._raise_on:
            from botocore.exceptions import ClientError
            raise ClientError({"Error": {"Code": "AccessDenied", "Message": "denied"}},
                              "PutObject")
        self.calls.append((filename, bucket, key, ExtraArgs or {}))


def make_outputs(tmp_path, *, with_story_image=True):
    """세션 폴더 하나를 통째로 흉내낸다 - 허용 목록 밖 파일도 일부러 섞는다."""
    run_dir = tmp_path / "2026-07-31"
    run_dir.mkdir()
    (run_dir / "frame_records.json").write_text("{}", encoding="utf-8")
    (run_dir / "walk_log.md").write_text("# 일지", encoding="utf-8")
    if with_story_image:
        (run_dir / "story_image.png").write_bytes(b"\x89PNG")
    (run_dir / "walk_flow.png").write_bytes(b"\x89PNG")
    panels = run_dir / "flow_panels"
    panels.mkdir()
    (panels / "panel_01.png").write_bytes(b"\x89PNG")
    payload = run_dir / "payload"
    payload.mkdir()
    (payload / "001_text.json").write_text("{}", encoding="utf-8")
    return run_dir


def test_upload_file_builds_s3_uri(tmp_path, monkeypatch):
    fake = FakeS3Client()
    monkeypatch.setattr(storage, "_client", lambda: fake)

    path = tmp_path / "walk_log.md"
    path.write_text("# 일지", encoding="utf-8")
    uri = upload_file(path, "walklog/2026-07-31/walk_log.md", bucket="my-bucket")

    assert uri == "s3://my-bucket/walklog/2026-07-31/walk_log.md"
    assert fake.calls == [
        (str(path), "my-bucket", "walklog/2026-07-31/walk_log.md",
         {"ContentType": "text/markdown; charset=utf-8"})
    ]


def test_upload_file_wraps_client_error(tmp_path, monkeypatch):
    fake = FakeS3Client(raise_on={"bad/key.png"})
    monkeypatch.setattr(storage, "_client", lambda: fake)

    path = tmp_path / "panel_01.png"
    path.write_bytes(b"\x89PNG")
    with pytest.raises(S3UploadError, match="업로드 실패"):
        upload_file(path, "bad/key.png", bucket="my-bucket")


def test_upload_outputs_only_uploads_allowlisted_files(tmp_path, monkeypatch):
    """일지 + 감성 이미지만 올리고, 세션 폴더의 나머지는 아무리 많아도 무시한다.

    frame_records.json(원자재), walk_flow.png/flow_panels(스토리보드 부산물),
    payload/(디버그 덤프)까지 전부 같은 세션에 있어도 새면 안 된다.
    """
    fake = FakeS3Client()
    monkeypatch.setattr(storage, "_client", lambda: fake)

    run_dir = make_outputs(tmp_path)
    uploaded = upload_outputs(run_dir, bucket="my-bucket", prefix="walklog")

    assert set(uploaded) == {"walk_log.md", "story_image.png"}
    assert uploaded["walk_log.md"] == "s3://my-bucket/walklog/2026-07-31/walk_log.md"
    assert uploaded["story_image.png"] == (
        "s3://my-bucket/walklog/2026-07-31/story_image.png"
    )
    uploaded_keys = {call[2] for call in fake.calls}
    assert len(uploaded_keys) == 2
    assert not any("payload" in key or "flow_panels" in key or "walk_flow" in key
                  or "frame_records" in key for key in uploaded_keys)


def test_upload_outputs_skips_missing_files_silently(tmp_path, monkeypatch):
    """--story-image 없이 일지만 만든 경우: 없는 파일은 조용히 건너뛴다."""
    fake = FakeS3Client()
    monkeypatch.setattr(storage, "_client", lambda: fake)

    run_dir = make_outputs(tmp_path, with_story_image=False)
    uploaded = upload_outputs(run_dir, bucket="my-bucket", prefix="walklog")

    assert set(uploaded) == {"walk_log.md"}


def test_upload_outputs_custom_files_override(tmp_path, monkeypatch):
    fake = FakeS3Client()
    monkeypatch.setattr(storage, "_client", lambda: fake)

    run_dir = make_outputs(tmp_path)
    uploaded = upload_outputs(run_dir, bucket="my-bucket", prefix="walklog",
                              files=("walk_flow.png",))

    assert set(uploaded) == {"walk_flow.png"}


def test_upload_outputs_without_prefix(tmp_path, monkeypatch):
    fake = FakeS3Client()
    monkeypatch.setattr(storage, "_client", lambda: fake)

    run_dir = make_outputs(tmp_path)
    uploaded = upload_outputs(run_dir, bucket="my-bucket", prefix="")

    assert uploaded["walk_log.md"] == "s3://my-bucket/2026-07-31/walk_log.md"


def test_upload_outputs_missing_dir(tmp_path):
    with pytest.raises(S3UploadError, match="업로드할 폴더가 없습니다"):
        upload_outputs(tmp_path / "nope")


def test_upload_outputs_includes_session_in_key(tmp_path, monkeypatch):
    """run_dir이 outputs/<날짜>/session<N>이면 키에 둘 다 들어가야 한다.

    run_dir.name만 쓰면 "session2"만 남고 날짜가 사라져 다른 날짜의
    session2와 충돌한다 - 세션 기능을 넣으면서 생긴 회귀를 잡는 테스트다.
    """
    outputs_dir = tmp_path / "outputs"
    monkeypatch.setattr(storage.config, "OUTPUTS_DIR", outputs_dir)
    fake = FakeS3Client()
    monkeypatch.setattr(storage, "_client", lambda: fake)

    run_dir = outputs_dir / "2026-08-03" / "session2"
    run_dir.mkdir(parents=True)
    (run_dir / "walk_log.md").write_text("# 일지", encoding="utf-8")

    uploaded = upload_outputs(run_dir, bucket="my-bucket", prefix="walklog")
    assert uploaded["walk_log.md"] == (
        "s3://my-bucket/walklog/2026-08-03/session2/walk_log.md"
    )
