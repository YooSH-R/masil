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


def make_outputs(tmp_path):
    run_dir = tmp_path / "2026-07-31"
    run_dir.mkdir()
    (run_dir / "frame_records.json").write_text("{}", encoding="utf-8")
    (run_dir / "walk_log.md").write_text("# 일지", encoding="utf-8")
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


def test_upload_outputs_mirrors_run_dir_and_skips_payload(tmp_path, monkeypatch):
    fake = FakeS3Client()
    monkeypatch.setattr(storage, "_client", lambda: fake)

    run_dir = make_outputs(tmp_path)
    uploaded = upload_outputs(run_dir, bucket="my-bucket", prefix="walklog")

    assert set(uploaded) == {
        "frame_records.json", "walk_log.md", "flow_panels/panel_01.png",
    }
    assert uploaded["walk_log.md"] == "s3://my-bucket/walklog/2026-07-31/walk_log.md"
    assert uploaded["flow_panels/panel_01.png"] == (
        "s3://my-bucket/walklog/2026-07-31/flow_panels/panel_01.png"
    )
    # payload/ 아래 파일은 업로드하지 않는다.
    assert not any("payload" in key for key in uploaded)
    uploaded_keys = {call[2] for call in fake.calls}
    assert not any("payload" in key for key in uploaded_keys)


def test_upload_outputs_without_prefix(tmp_path, monkeypatch):
    fake = FakeS3Client()
    monkeypatch.setattr(storage, "_client", lambda: fake)

    run_dir = make_outputs(tmp_path)
    uploaded = upload_outputs(run_dir, bucket="my-bucket", prefix="")

    assert uploaded["walk_log.md"] == "s3://my-bucket/2026-07-31/walk_log.md"


def test_upload_outputs_missing_dir(tmp_path):
    with pytest.raises(S3UploadError, match="업로드할 폴더가 없습니다"):
        upload_outputs(tmp_path / "nope")
