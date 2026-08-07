"""run.py 검증 - 이벤트 패널(panels)이 기본 산출물인지.

run.py는 스테이지1(walk_log)/스테이지2(flow_image)를 그대로 호출하는
얇은 조립 스크립트라, 여기서는 그 두 진입점을 가짜로 바꿔 끼우고
"어떤 인자로 불렸는가"만 본다. 실제 API 호출은 다른 테스트가 담당한다.
"""

from __future__ import annotations

import run as run_module


def test_run_default_panels_true_calls_flow_image_with_panels_mode(monkeypatch, capsys):
    """플래그 없이 실행하면 panels=True가 기본값이라 flow_image가 panels 모드로 불린다."""
    flow_calls: list[list[str]] = []
    monkeypatch.setattr("walklog.cli.walk_log.main", lambda argv: 0)
    monkeypatch.setattr("walklog.cli.flow_image.main",
                        lambda argv: flow_calls.append(argv) or 0)

    code = run_module.main([])

    assert code == 0
    assert "이벤트 패널 4장" in capsys.readouterr().err
    assert any("--mode" in argv and "panels" in argv for argv in flow_calls)


def test_run_no_panels_skips_stage2(monkeypatch, capsys):
    """--no-panels를 주면 panels=False가 되어 flow_image 자체가 불리지 않는다."""
    flow_calls: list[list[str]] = []
    monkeypatch.setattr("walklog.cli.walk_log.main", lambda argv: 0)
    monkeypatch.setattr("walklog.cli.flow_image.main",
                        lambda argv: flow_calls.append(argv) or 0)

    code = run_module.main(["--no-panels"])

    assert code == 0
    assert not flow_calls
    assert "이벤트 패널 4장" not in capsys.readouterr().err


def test_run_panels_flag_explicit_still_true(monkeypatch, capsys):
    """--panels를 명시해도(기존 호출부 호환) 여전히 패널 스테이지가 돈다."""
    flow_calls: list[list[str]] = []
    monkeypatch.setattr("walklog.cli.walk_log.main", lambda argv: 0)
    monkeypatch.setattr("walklog.cli.flow_image.main",
                        lambda argv: flow_calls.append(argv) or 0)

    code = run_module.main(["--panels"])

    assert code == 0
    assert any("panels" in argv for argv in flow_calls)


def test_run_board_flag_calls_journal_mode_instead_of_panels(monkeypatch, capsys):
    """--board를 켜면 panels 대신 기존 journal 모드(보드 합성)를 호출한다."""
    flow_calls: list[list[str]] = []
    monkeypatch.setattr("walklog.cli.walk_log.main", lambda argv: 0)
    monkeypatch.setattr("walklog.cli.flow_image.main",
                        lambda argv: flow_calls.append(argv) or 0)

    code = run_module.main(["--board"])

    assert code == 0
    assert len(flow_calls) == 1
    assert "journal" in flow_calls[0]
    assert "panels" not in flow_calls[0]
    err = capsys.readouterr().err
    assert "산책일지 이미지(journal)" in err
    assert "이벤트 패널 4장" not in err


# ============================================================ story_image opt-in

def test_run_default_omits_story_image(monkeypatch, capsys):
    """플래그 없이 실행하면 story_image=False라 walk_log에 --story-image를 안 넘긴다."""
    log_calls: list[list[str]] = []
    monkeypatch.setattr("walklog.cli.walk_log.main",
                        lambda argv: log_calls.append(argv) or 0)
    monkeypatch.setattr("walklog.cli.flow_image.main", lambda argv: 0)

    code = run_module.main([])

    assert code == 0
    assert "--story-image" not in log_calls[0]
    assert "감성 이미지" not in capsys.readouterr().err


def test_run_story_image_flag_forwarded_to_walk_log(monkeypatch, capsys):
    """--story-image를 켜면 walk_log에 --story-image(+--verify-image)가 그대로 전달된다."""
    log_calls: list[list[str]] = []
    monkeypatch.setattr("walklog.cli.walk_log.main",
                        lambda argv: log_calls.append(argv) or 0)
    monkeypatch.setattr("walklog.cli.flow_image.main", lambda argv: 0)

    code = run_module.main(["--story-image"])

    assert code == 0
    assert "--story-image" in log_calls[0]
    assert "--verify-image" in log_calls[0]
    assert "감성 이미지" in capsys.readouterr().err


def test_run_story_image_no_verify_image_omits_flag(monkeypatch):
    log_calls: list[list[str]] = []
    monkeypatch.setattr("walklog.cli.walk_log.main",
                        lambda argv: log_calls.append(argv) or 0)
    monkeypatch.setattr("walklog.cli.flow_image.main", lambda argv: 0)

    run_module.main(["--story-image", "--no-verify-image"])

    assert "--story-image" in log_calls[0]
    assert "--verify-image" not in log_calls[0]
