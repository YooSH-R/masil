"""config.py의 세션 폴더 계산 검증.

하루에 산책을 여러 번 다녀오면 session1, session2, ... 로 나뉘어야
이전 산책 기록이 덮어써지지 않는다. 이 파일은 그 폴더 계산만 본다.
CLI가 "새 세션을 만들지 최근 세션을 이어 쓸지" 고르는 로직은
test_cli.py의 resolve_run_dir 테스트에서 다룬다.
"""

from __future__ import annotations

from walklog import config


def test_list_sessions_empty_when_date_dir_missing(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "OUTPUTS_DIR", tmp_path)
    assert config.list_sessions("2026-08-03") == []


def test_list_sessions_returns_sorted_numbers(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "OUTPUTS_DIR", tmp_path)
    day_dir = tmp_path / "2026-08-03"
    for name in ("session2", "session1", "session10"):
        (day_dir / name).mkdir(parents=True)

    assert config.list_sessions("2026-08-03") == [1, 2, 10]


def test_list_sessions_ignores_non_session_dirs_and_files(tmp_path, monkeypatch):
    """flow_panels, payload 같은 세션 아닌 하위 폴더는 세션으로 잡히지 않는다."""
    monkeypatch.setattr(config, "OUTPUTS_DIR", tmp_path)
    day_dir = tmp_path / "2026-08-03"
    (day_dir / "session1").mkdir(parents=True)
    (day_dir / "flow_panels").mkdir(parents=True)
    (day_dir / "session_backup").mkdir(parents=True)   # session으로 시작하지만 숫자가 아니다
    (day_dir / "walk_log.md").write_text("x", encoding="utf-8")   # 과거 평면 배치 잔재

    assert config.list_sessions("2026-08-03") == [1]


def test_run_dir_with_session_creates_nested_folder(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "OUTPUTS_DIR", tmp_path)
    path = config.run_dir("2026-08-03", session=2)

    assert path == tmp_path / "2026-08-03" / "session2"
    assert path.is_dir()


def test_run_dir_without_session_matches_old_flat_layout(tmp_path, monkeypatch):
    """session을 안 주면 세션 나누기 전 동작(날짜 폴더 바로 아래)과 같다."""
    monkeypatch.setattr(config, "OUTPUTS_DIR", tmp_path)
    path = config.run_dir("2026-08-03")

    assert path == tmp_path / "2026-08-03"
    assert path.is_dir()


def test_run_dir_no_create(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "OUTPUTS_DIR", tmp_path)
    path = config.run_dir("2026-08-03", session=1, create=False)
    assert not path.exists()
