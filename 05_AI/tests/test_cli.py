"""diagnostics + cli 검증.

diagnostics의 핵심은 "거짓 통과를 만들지 않는가"다.
분할 전에는 merge 모드로 진단하면 카나리아가 user 텍스트에 합쳐져
"systemInstruction 정상 반영"이라는 잘못된 결론이 나왔다.
"""

from __future__ import annotations

import argparse
import base64
import io
import json
from pathlib import Path

import pytest
from PIL import Image

from walklog import config, diagnostics
from walklog.cli import common, flow_image, walk_log
from walklog.records import dump_records, iter_frames, FrameRecord, WalkInfo

REAL_NAMES = [
    "f_0000128_t000m08.53s.jpg",
    "f_0000448_t000m29.87s.jpg",
    "f_0000960_t001m04.00s.jpg",
]


def touch_frames(directory, names=REAL_NAMES):
    directory.mkdir(parents=True, exist_ok=True)
    for name in names:
        Image.new("RGB", (48, 36), (90, 120, 100)).save(directory / name, "JPEG")
    return directory


def png_bytes():
    buffer = io.BytesIO()
    Image.new("RGB", (400, 300), (200, 210, 180)).save(buffer, "PNG")
    return buffer.getvalue()


def observation(**over):
    base = {"scene": "하천 옆 산책로", "location_type": "하천변", "surface": "데크",
            "time_of_day": "아침", "weather": "맑음", "objects": ["억새", "다리"],
            "atmosphere": ["시원함"], "unreadable": False,
            "confidence": {"time_of_day": 1.0, "weather": 0.9, "location_type": 0.9}}
    base.update(over)
    return base


# ============================================================ 가짜 세션

class FakeResponse:
    def __init__(self, payload=None, status=200, text="{}"):
        self._payload = payload or {}
        self.status_code = status
        self.ok = 200 <= status < 300
        self.text = text

    def json(self):
        return self._payload


def text_response(text):
    return FakeResponse({
        "candidates": [{"content": {"parts": [{"text": text}]},
                        "finishReason": "STOP"}],
        "usageMetadata": {"totalTokenCount": 10, "candidatesTokenCount": 5}})


class FakeSession:
    def __init__(self, *responses):
        self.responses = list(responses)
        self.sent = []

    def post(self, url, headers=None, json=None, timeout=None):
        self.sent.append({"url": url, "body": json})
        return self.responses.pop(0) if self.responses else text_response("ok")

    def close(self):
        pass


# ============================================================ diagnostics

def test_system_instruction_supported():
    session = FakeSession(text_response("SYSTEM_OK"))
    result = diagnostics.Diagnostics(key="k", session=session).system_instruction()
    assert result.status == "ok"


def test_system_instruction_ignored_suggests_merge():
    """프록시가 systemInstruction을 버리면 카나리아가 응답에 없다."""
    session = FakeSession(text_response("오늘은 맑고 따뜻합니다."))
    result = diagnostics.Diagnostics(key="k", session=session).system_instruction()

    assert result.status == "unsupported"
    assert "merge" in result.hint


def test_system_instruction_probe_forces_correct_mode(monkeypatch):
    """진단은 전역 SYSTEM_MODE와 무관하게 system_instruction 경로를 써야 한다.

    분할 전 버그: 전역이 merge면 카나리아가 user 텍스트에 합쳐져 전달되므로
    모델이 당연히 SYSTEM_OK를 출력하고 "정상 반영"이라는 거짓 통과가 나왔다.
    """
    monkeypatch.setattr(config, "SYSTEM_MODE", "merge")
    session = FakeSession(text_response("SYSTEM_OK"))
    diagnostics.Diagnostics(key="k", session=session).system_instruction()

    body = session.sent[0]["body"]
    assert "systemInstruction" in body            # merge로 합쳐지지 않았다
    user_text = body["contents"][0]["parts"][-1]["text"]
    assert "SYSTEM_OK" not in user_text           # 카나리아가 user에 새지 않았다


def test_system_instruction_inconclusive_on_empty():
    """응답이 비면 '미지원'이 아니라 '판정 불가'다."""
    session = FakeSession(FakeResponse({
        "candidates": [{"content": {"parts": [{"text": "생각", "thought": True}]},
                        "finishReason": "MAX_TOKENS"}]}))
    result = diagnostics.Diagnostics(key="k", session=session).system_instruction()

    assert result.status == "inconclusive"
    assert "max_output_tokens" in result.hint


def test_response_schema_supported():
    session = FakeSession(text_response('{"ok": true}'))
    result = diagnostics.Diagnostics(key="k", session=session).response_schema()
    assert result.status == "ok"


def test_response_schema_rejected_suggests_env():
    session = FakeSession(FakeResponse(status=400, text="Unknown field responseSchema"))
    result = diagnostics.Diagnostics(key="k", session=session).response_schema()

    assert result.status == "unsupported"
    assert "GMS_USE_RESPONSE_SCHEMA=0" in result.hint


def test_thinking_config_probe_sends_the_field():
    session = FakeSession(text_response("2"))
    result = diagnostics.Diagnostics(key="k", session=session).thinking_config()

    assert result.status == "ok"
    config_sent = session.sent[0]["body"]["generationConfig"]
    assert config_sent["thinkingConfig"] == {"thinkingBudget": 0}


def test_thinking_config_rejected():
    session = FakeSession(FakeResponse(status=400, text="Unknown field thinkingConfig"))
    result = diagnostics.Diagnostics(key="k", session=session).thinking_config()
    assert result.status == "unsupported"


def test_env_suggestions_and_report():
    session = FakeSession(
        text_response("맑습니다"),                                  # system 무시
        FakeResponse(status=400, text="no schema"),                 # schema 거부
        text_response("2"),                                         # thinking OK
    )
    results = diagnostics.Diagnostics(key="k", session=session).run_all()

    assert diagnostics.env_suggestions(results) == [
        "GMS_SYSTEM_MODE=merge", "GMS_USE_RESPONSE_SCHEMA=0"]

    report = diagnostics.format_report(results)
    assert "[X] systemInstruction" in report and "[O] thinkingConfig" in report


def test_report_when_all_supported():
    session = FakeSession(text_response("SYSTEM_OK"), text_response('{"ok":true}'),
                          text_response("2"))
    results = diagnostics.Diagnostics(key="k", session=session).run_all()
    assert diagnostics.env_suggestions(results) == []
    assert "설정 변경이 필요 없습니다" in diagnostics.format_report(results)


# ============================================================ CLI 공통 준비

class FakeClient:
    """CLI가 쓰는 클라이언트 자리에 꽂는다."""

    def __init__(self):
        self.calls = []
        self.total_tokens = 1234
        self.closed = False

    def generate_json(self, spec, **kwargs):
        self.calls.append(("json", spec, kwargs))
        return observation()

    def generate_text(self, spec, **kwargs):
        from walklog import prompts as P
        self.calls.append(("text", spec, kwargs))
        if spec is P.PANEL_CAPTION_WRITER:
            return "아침 하천길"
        if spec in (P.IMAGE_PROMPT_WRITER, P.FLOW_IMAGE_WRITER):
            return "riverside path, morning light, reeds"
        return "## 2026-07-28 산책 일지\n\n**한 줄 요약**: 아침 하천길\n\n본문."

    def generate_image(self, prompt, **kwargs):
        self.calls.append(("image", prompt, kwargs))
        return png_bytes()

    def close(self):
        self.closed = True


@pytest.fixture
def fake_client(monkeypatch):
    client = FakeClient()
    monkeypatch.setattr("walklog.cli.common.build_client",
                        lambda args, run_dir: client)
    return client


@pytest.fixture(autouse=True)
def no_real_s3_upload(monkeypatch):
    """S3 업로드가 기본값(True)이 되면서, 여기 있는 CLI 종단 테스트들이
    아무 조치 없이 실행되면 실제 AWS 자격증명 체인(IMDS 프로브 등)을 건드려
    느려지고, 자격증명이 있는 환경에서는 실제로 업로드까지 될 수 있다.
    업로드 로직 자체는 test_storage.py가 가짜 S3 클라이언트로 검증하므로,
    여기서는 호출만 막는다.
    """
    monkeypatch.setattr(common, "upload_if_requested", lambda args, run_dir: None)


# ============================================================ 세션 폴더 계산

def test_resolve_run_dir_new_session_increments(tmp_path, monkeypatch):
    """new_session=True(run_walk_log.py 기본)는 부를 때마다 다음 번호를 새로 만든다."""
    monkeypatch.setattr(config, "OUTPUTS_DIR", tmp_path)
    args = argparse.Namespace(out_dir=None, date="2026-08-03", session=None)

    first = common.resolve_run_dir(args)
    second = common.resolve_run_dir(args)

    assert first == tmp_path / "2026-08-03" / "session1"
    assert second == tmp_path / "2026-08-03" / "session2"


def test_resolve_run_dir_latest_session_reused(tmp_path, monkeypatch):
    """new_session=False(run_flow_image.py)는 새로 만들지 않고 최근 세션을 그대로 쓴다."""
    monkeypatch.setattr(config, "OUTPUTS_DIR", tmp_path)
    args = argparse.Namespace(out_dir=None, date="2026-08-03", session=None)

    created = common.resolve_run_dir(args)
    reused = common.resolve_run_dir(args, new_session=False)

    assert created == reused == tmp_path / "2026-08-03" / "session1"


def test_resolve_run_dir_latest_session_when_none_exist_yet(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "OUTPUTS_DIR", tmp_path)
    args = argparse.Namespace(out_dir=None, date="2026-08-03", session=None)

    assert common.resolve_run_dir(args, new_session=False) == \
        tmp_path / "2026-08-03" / "session1"


def test_resolve_run_dir_explicit_session_overrides_auto(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "OUTPUTS_DIR", tmp_path)
    args = argparse.Namespace(out_dir=None, date="2026-08-03", session=5)

    assert common.resolve_run_dir(args) == tmp_path / "2026-08-03" / "session5"


def test_resolve_run_dir_out_dir_bypasses_sessions(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "OUTPUTS_DIR", tmp_path)
    custom = tmp_path / "anywhere"
    args = argparse.Namespace(out_dir=custom, date="2026-08-03", session=None)

    assert common.resolve_run_dir(args) == custom
    assert config.list_sessions("2026-08-03") == []


def test_run_label_under_outputs_dir(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "OUTPUTS_DIR", tmp_path)
    assert common.run_label(tmp_path / "2026-08-03" / "session2") == "2026-08-03/session2"


def test_run_label_outside_outputs_dir(tmp_path):
    assert common.run_label(tmp_path / "elsewhere") == "elsewhere"


# ============================================================ walk_log CLI

def test_walk_log_end_to_end(tmp_path, fake_client):
    frames = touch_frames(tmp_path / "frames")
    out = tmp_path / "out"

    code = walk_log.main([
        "--frames", str(frames), "--out-dir", str(out),
        "--date", "2026-07-28", "--started-at", "2026-07-28T08:12:03",
        "--location", "OO천 산책로", "--style", "emotional",
    ])

    assert code == 0
    records_file = out / config.RECORDS_NAME
    diary_file = out / config.DIARY_NAME
    assert records_file.is_file() and diary_file.is_file()

    saved = json.loads(records_file.read_text(encoding="utf-8"))
    assert saved["frame_count"] == 3
    assert saved["prompt_version"]
    assert saved["walk"]["started_at"] == "2026-07-28T08:12:03"

    # shot_datetime 이 Stage 1 호출까지 도달했는지
    first = fake_client.calls[0][2]
    assert first["shot_datetime"] == "2026-07-28 08:12:11"
    assert first["location"] == "OO천 산책로"

    # 문체가 반영됐는지
    diary_call = next(c for c in fake_client.calls
                      if c[0] == "text" and "json_lines" in c[2])
    assert "혼잣말하듯" in diary_call[1].system
    assert fake_client.closed


def _many_frame_names(count):
    """10초 간격으로 늘어놓은 합성 프레임 이름 count개. 적응형 표본 크기 테스트용."""
    return [f"f_{i:07d}_t{(i * 10) // 60:03d}m{(i * 10) % 60:05.2f}s.jpg"
            for i in range(count)]


def test_walk_log_adaptive_sample_size_default(tmp_path, fake_client, capsys):
    """--quarters 를 생략하면 전체 프레임의 약 10%(4~12장)로 자동 계산된다."""
    frames = touch_frames(tmp_path / "frames", _many_frame_names(50))

    code = walk_log.main(["--frames", str(frames), "--out-dir", str(tmp_path / "o"),
                          "--no-diary"])

    assert code == 0
    json_calls = [c for c in fake_client.calls if c[0] == "json"]
    assert len(json_calls) == 5   # round(50 * 0.10)
    assert "5등분 (전체 50장의 약 10%, 4~12 범위)" in capsys.readouterr().err


def test_walk_log_quarters_explicit_skips_auto(tmp_path, fake_client, capsys):
    """--quarters를 직접 주면 자동 계산을 건너뛰고 그 값이 그대로 쓰인다."""
    frames = touch_frames(tmp_path / "frames", _many_frame_names(50))

    code = walk_log.main(["--frames", str(frames), "--out-dir", str(tmp_path / "o"),
                          "--no-diary", "--quarters", "3"])

    assert code == 0
    json_calls = [c for c in fake_client.calls if c[0] == "json"]
    assert len(json_calls) == 3
    assert "3등분 (직접 지정)" in capsys.readouterr().err


def test_walk_log_diary_footer_has_time_range(tmp_path, fake_client):
    """일지 푸터에 시작~종료 시각이 코드로 계산되어 붙는지."""
    frames = touch_frames(tmp_path / "frames")

    code = walk_log.main(["--frames", str(frames), "--out-dir", str(tmp_path / "o"),
                          "--started-at", "2026-07-28T08:12:03"])

    assert code == 0
    diary = (tmp_path / "o" / config.DIARY_NAME).read_text(encoding="utf-8")
    assert "- 시간: 08:12 ~ 08:13" in diary   # 마지막 프레임 64.0s -> 08:13:07


def test_walk_log_diary_no_footer_without_started_at(tmp_path, fake_client):
    """시작 시각을 모르면 '불명 ~ 불명' 대신 줄 자체를 생략한다."""
    frames = touch_frames(tmp_path / "frames")

    code = walk_log.main(["--frames", str(frames), "--out-dir", str(tmp_path / "o")])

    assert code == 0
    diary = (tmp_path / "o" / config.DIARY_NAME).read_text(encoding="utf-8")
    assert "- 시간:" not in diary


def test_walk_log_limit_and_no_diary(tmp_path, fake_client):
    frames = touch_frames(tmp_path / "frames")
    out = tmp_path / "out"

    code = walk_log.main(["--frames", str(frames), "--out-dir", str(out),
                          "--limit", "2", "--no-diary"])

    assert code == 0
    assert (out / config.RECORDS_NAME).is_file()
    assert not (out / config.DIARY_NAME).exists()
    assert len([c for c in fake_client.calls if c[0] == "json"]) == 2


def test_walk_log_no_thinking_applies_budget(tmp_path, fake_client):
    frames = touch_frames(tmp_path / "frames", REAL_NAMES[:1])
    walk_log.main(["--frames", str(frames), "--out-dir", str(tmp_path / "o"),
                   "--no-diary", "--no-thinking"])
    assert fake_client.calls[0][1].thinking_budget == 0


def test_walk_log_temperature_override(tmp_path, fake_client):
    frames = touch_frames(tmp_path / "frames", REAL_NAMES[:1])
    walk_log.main(["--frames", str(frames), "--out-dir", str(tmp_path / "o"),
                   "--no-diary", "--temperature", "0.0"])
    assert fake_client.calls[0][1].temperature == 0.0


def test_walk_log_reuses_records(tmp_path, fake_client):
    """--no-observe 로 Stage 1을 건너뛰고 일지만 다시 쓴다.

    문체를 비교할 때 VLM을 다시 부르지 않아도 된다.
    """
    frames = touch_frames(tmp_path / "frames")
    metas = iter_frames(frames)
    records = [FrameRecord(observation=observation(), meta=m) for m in metas]
    path = dump_records(records, tmp_path / "old" / config.RECORDS_NAME,
                        walk=WalkInfo(date="2026-07-28"))

    code = walk_log.main(["--records", str(path), "--no-observe",
                          "--frames", str(frames),
                          "--out-dir", str(tmp_path / "out"), "--style", "workout"])

    assert code == 0
    assert not [c for c in fake_client.calls if c[0] == "json"]   # VLM 미호출
    assert (tmp_path / "out" / config.DIARY_NAME).is_file()


def test_walk_log_no_observe_without_records(tmp_path, fake_client, capsys):
    assert walk_log.main(["--no-observe", "--out-dir", str(tmp_path)]) == 1
    assert "--records 와 함께" in capsys.readouterr().err


def test_walk_log_missing_frames_dir(tmp_path, fake_client, capsys):
    code = walk_log.main(["--frames", str(tmp_path / "nope"),
                          "--out-dir", str(tmp_path / "o")])
    assert code == 1
    assert "프레임 폴더가 없습니다" in capsys.readouterr().err


def test_walk_log_dump_payload_dir(tmp_path, monkeypatch):
    """--dump-payload 가 실제 클라이언트에 dump_dir를 넘기는지."""
    captured = {}

    def spy(args, run_dir):
        captured["dump"] = args.dump_payload
        captured["dir"] = run_dir
        return FakeClient()

    monkeypatch.setattr("walklog.cli.common.build_client", spy)
    frames = touch_frames(tmp_path / "frames", REAL_NAMES[:1])
    walk_log.main(["--frames", str(frames), "--out-dir", str(tmp_path / "o"),
                   "--no-diary", "--dump-payload"])
    assert captured["dump"] is True


def test_walk_log_second_walk_same_day_gets_own_session(tmp_path, fake_client, monkeypatch):
    """하루에 산책을 두 번 다녀와도 두 번째 실행이 첫 번째 기록을 덮어쓰지 않는다.

    --out-dir 를 안 주면(실제 사용자가 매번 쓰는 방식) 세션이 자동으로 나뉜다.
    """
    monkeypatch.setattr(config, "OUTPUTS_DIR", tmp_path / "outputs")
    frames = touch_frames(tmp_path / "frames")

    code1 = walk_log.main(["--frames", str(frames), "--date", "2026-08-03"])
    code2 = walk_log.main(["--frames", str(frames), "--date", "2026-08-03"])

    assert code1 == 0 and code2 == 0
    day_dir = tmp_path / "outputs" / "2026-08-03"
    assert (day_dir / "session1" / config.DIARY_NAME).is_file()
    assert (day_dir / "session2" / config.DIARY_NAME).is_file()
    assert (day_dir / "session1" / config.RECORDS_NAME).is_file()
    assert (day_dir / "session2" / config.RECORDS_NAME).is_file()


def test_walk_log_check_runs_diagnostics(monkeypatch, capsys):
    session = FakeSession(text_response("SYSTEM_OK"), text_response('{"ok":true}'),
                          text_response("2"))
    original = diagnostics.Diagnostics          # 람다 안에서 패치된 이름을 다시 부르면 무한 재귀
    monkeypatch.setattr(diagnostics, "Diagnostics",
                        lambda **kw: original(key="k", session=session))

    assert walk_log.main(["--check"]) == 0
    assert "프록시 지원 진단" in capsys.readouterr().out


# ============================================================ walk_log CLI (실내 배제)

def test_walk_log_allow_indoor_skips_replacement_and_filtering(tmp_path, monkeypatch, capsys):
    """--allow-indoor면 대체 관찰도, 다운스트림 outdoor() 필터도 건너뛴다.

    (실내 테스트 영상용 - 배제 로직이 개입하면 안 된다)
    """
    class IndoorClient(FakeClient):
        def generate_json(self, spec, **kwargs):
            self.calls.append(("json", spec, kwargs))
            return observation(indoor=True)

    client = IndoorClient()
    monkeypatch.setattr("walklog.cli.common.build_client",
                        lambda args, run_dir: client)
    frames = touch_frames(tmp_path / "frames")

    code = walk_log.main(["--frames", str(frames), "--out-dir", str(tmp_path / "o"),
                          "--allow-indoor"])

    assert code == 0
    saved = json.loads((tmp_path / "o" / config.RECORDS_NAME).read_text(encoding="utf-8"))
    assert all(r["observation"]["indoor"] for r in saved["records"])
    err = capsys.readouterr().err
    assert "[실내 배제]" not in err
    assert "실내 기록을 포함해" not in err


def test_walk_log_default_replaces_indoor_frames(tmp_path, monkeypatch, capsys):
    """플래그 없이 실행하면(기본값) 실내 프레임을 대체 관찰하려 시도한다."""
    class IndoorClient(FakeClient):
        def generate_json(self, spec, **kwargs):
            self.calls.append(("json", spec, kwargs))
            return observation(indoor=True)

    client = IndoorClient()
    monkeypatch.setattr("walklog.cli.common.build_client",
                        lambda args, run_dir: client)
    frames = touch_frames(tmp_path / "frames")

    code = walk_log.main(["--frames", str(frames), "--out-dir", str(tmp_path / "o"),
                          "--no-diary"])

    assert code == 0
    err = capsys.readouterr().err
    assert "실내 기록을 포함해 그대로 진행합니다" in err   # 전부 실내라 폴백 경고가 남는다


# ============================================================ flow_image CLI

def prepare_records(tmp_path):
    frames = touch_frames(tmp_path / "frames")
    metas = iter_frames(frames)
    records = [
        FrameRecord(observation=observation(location_type="주택가"), meta=metas[0]),
        FrameRecord(observation=observation(location_type="하천변"), meta=metas[1]),
        FrameRecord(observation=observation(location_type="하천변"), meta=metas[2]),
    ]
    path = dump_records(records, tmp_path / "out" / config.RECORDS_NAME,
                        walk=WalkInfo(date="2026-07-28"))
    return frames, path


def test_flow_image_dry_run_makes_no_calls(tmp_path, fake_client, capsys):
    frames, path = prepare_records(tmp_path)

    code = flow_image.main(["--records", str(path), "--frames", str(frames),
                            "--mode", "storyboard", "--dry-run", "-n", "2"])

    assert code == 0
    assert not fake_client.calls
    out = capsys.readouterr().out
    assert "선정된 장면" in out and "weight=" in out


def test_flow_image_storyboard(tmp_path, fake_client):
    frames, path = prepare_records(tmp_path)
    out_dir = tmp_path / "sb"

    code = flow_image.main(["--records", str(path), "--frames", str(frames),
                            "--out-dir", str(out_dir), "--mode", "storyboard", "-n", "2"])

    assert code == 0
    assert (out_dir / config.FLOW_IMAGE_NAME).is_file()
    panels = sorted(p.name for p in (out_dir / config.PANELS_DIRNAME).iterdir())
    assert panels == ["panel_01.png", "panel_02.png"]
    assert len([c for c in fake_client.calls if c[0] == "image"]) == 2


def test_flow_image_single_mode(tmp_path, fake_client):
    frames, path = prepare_records(tmp_path)
    out = tmp_path / "one.png"

    code = flow_image.main(["--records", str(path), "--frames", str(frames),
                            "--out", str(out), "--out-dir", str(tmp_path / "s"),
                            "--mode", "single"])

    assert code == 0 and out.is_file()
    assert len([c for c in fake_client.calls if c[0] == "image"]) == 1
    from walklog import prompts as P
    assert any(c[1] is P.FLOW_IMAGE_WRITER for c in fake_client.calls if c[0] == "text")


def test_flow_image_no_caption_llm(tmp_path, fake_client):
    frames, path = prepare_records(tmp_path)
    flow_image.main(["--records", str(path), "--frames", str(frames),
                     "--out-dir", str(tmp_path / "nc"), "--mode", "storyboard",
                     "-n", "2", "--no-caption-llm"])
    from walklog import prompts as P
    assert not any(c[1] is P.PANEL_CAPTION_WRITER for c in fake_client.calls)


def test_flow_image_no_ref_skips_reference(tmp_path, fake_client):
    frames, path = prepare_records(tmp_path)
    flow_image.main(["--records", str(path), "--frames", str(frames),
                     "--out-dir", str(tmp_path / "nr"), "--mode", "storyboard",
                     "-n", "1", "--no-ref"])
    image_calls = [c for c in fake_client.calls if c[0] == "image"]
    assert image_calls[0][2]["reference"] is None


def test_flow_image_missing_records(tmp_path, fake_client, capsys):
    code = flow_image.main(["--records", str(tmp_path / "nope.json"),
                            "--out-dir", str(tmp_path / "o")])
    assert code == 1
    err = capsys.readouterr().err
    assert "찾을 수 없습니다" in err and "run_walk_log.py" in err


def test_flow_image_all_unreadable(tmp_path, fake_client, capsys):
    frames = touch_frames(tmp_path / "frames", REAL_NAMES[:1])
    metas = iter_frames(frames)
    records = [FrameRecord(observation=observation(unreadable=True), meta=metas[0])]
    path = dump_records(records, tmp_path / "out" / config.RECORDS_NAME)

    code = flow_image.main(["--records", str(path), "--frames", str(frames),
                            "--out-dir", str(tmp_path / "o"), "--dry-run"])
    assert code == 1
    assert "모두 unreadable" in capsys.readouterr().err


def test_flow_image_defaults_to_latest_session(tmp_path, fake_client, monkeypatch):
    """--out-dir/--session 을 안 주면 가장 최근 세션의 관찰 기록을 읽고
    그 세션 폴더에 삽화를 쓴다 - 새 세션을 만들지 않는다.
    """
    monkeypatch.setattr(config, "OUTPUTS_DIR", tmp_path / "outputs")
    frames = touch_frames(tmp_path / "frames")

    walk_log.main(["--frames", str(frames), "--date", "2026-08-03", "--no-diary"])
    walk_log.main(["--frames", str(frames), "--date", "2026-08-03", "--no-diary"])

    code = flow_image.main(["--frames", str(frames), "--date", "2026-08-03",
                            "--mode", "storyboard", "-n", "2"])

    assert code == 0
    day_dir = tmp_path / "outputs" / "2026-08-03"
    assert (day_dir / "session2" / config.FLOW_IMAGE_NAME).is_file()
    assert not (day_dir / "session1" / config.FLOW_IMAGE_NAME).exists()
    assert not (day_dir / "session3").exists()


# ============================================================ flow_image --mode journal

def test_flow_image_journal_dry_run(tmp_path, fake_client, capsys):
    frames, path = prepare_records(tmp_path)

    code = flow_image.main(["--records", str(path), "--frames", str(frames),
                            "--mode", "journal", "--dry-run", "--events", "2"])

    assert code == 0
    assert not fake_client.calls
    out = capsys.readouterr().out
    assert "선정된 이벤트" in out and "score=" in out


def test_flow_image_journal_creates_expected_file(tmp_path, fake_client):
    frames, path = prepare_records(tmp_path)
    out_dir = tmp_path / "journal_out"

    code = flow_image.main(["--records", str(path), "--frames", str(frames),
                            "--out-dir", str(out_dir), "--mode", "journal",
                            "--events", "2"])

    assert code == 0
    assert (out_dir / config.JOURNAL_NAME).is_file()
    assert not (out_dir / config.FLOW_IMAGE_NAME).exists()
    assert len([c for c in fake_client.calls if c[0] == "image"]) == 2


def test_flow_image_journal_note_parsed_from_diary(tmp_path):
    """세션 폴더에 walk_log.md가 있으면 '한 줄 요약' 줄을 그대로 note로 쓴다."""
    from walklog.cli.flow_image import _diary_note

    (tmp_path / config.DIARY_NAME).write_text(
        "## 2026-07-28 산책 일지\n\n**한 줄 요약**: 비 온 뒤 조용한 하천길\n\n본문.",
        encoding="utf-8")
    assert _diary_note(tmp_path) == "비 온 뒤 조용한 하천길"


def test_flow_image_journal_note_empty_without_diary(tmp_path):
    from walklog.cli.flow_image import _diary_note
    assert _diary_note(tmp_path) == ""


# ============================================================ flow_image --mode panels (기본값)

def test_flow_image_panels_dry_run(tmp_path, fake_client, capsys):
    frames, path = prepare_records(tmp_path)

    code = flow_image.main(["--records", str(path), "--frames", str(frames),
                            "--dry-run", "--events", "2"])

    assert code == 0
    assert not fake_client.calls
    out = capsys.readouterr().out
    assert "선정된 이벤트" in out and "score=" in out


def test_flow_image_panels_is_default_mode(tmp_path, fake_client):
    """--mode를 생략하면 panels가 기본값이라 flow_panels/ 없이 세션 폴더에 바로
    패널이 생기고 보드/캡션은 없다."""
    frames, path = prepare_records(tmp_path)
    out_dir = tmp_path / "panels_out"

    code = flow_image.main(["--records", str(path), "--frames", str(frames),
                            "--out-dir", str(out_dir), "--events", "2"])

    assert code == 0
    assert not (out_dir / config.JOURNAL_NAME).exists()
    assert not (out_dir / config.FLOW_IMAGE_NAME).exists()
    assert not (out_dir / config.PANELS_DIRNAME).exists()
    panels = sorted(p.name for p in out_dir.glob("event_*.png"))
    assert panels == ["event_01.png", "event_02.png"]
    image_calls = [c for c in fake_client.calls if c[0] == "image"]
    assert len(image_calls) == 2
    from walklog import prompts as P
    assert not any(c[1] is P.PANEL_CAPTION_WRITER for c in fake_client.calls)


def test_flow_image_panels_default_omits_reference(tmp_path, fake_client):
    """panels 기본값은 참조 없음이다(2026-08-05 실측: 참조 포함 생성 86% 화풍 불합격)."""
    frames, path = prepare_records(tmp_path)

    flow_image.main(["--records", str(path), "--frames", str(frames),
                     "--out-dir", str(tmp_path / "nr"), "--events", "1"])

    image_calls = [c for c in fake_client.calls if c[0] == "image"]
    assert image_calls[0][2]["reference"] is None


def test_flow_image_panels_use_reference_flag_passes_reference(tmp_path, fake_client):
    frames, path = prepare_records(tmp_path)

    flow_image.main(["--records", str(path), "--frames", str(frames),
                     "--out-dir", str(tmp_path / "wr"), "--events", "1",
                     "--use-reference"])

    image_calls = [c for c in fake_client.calls if c[0] == "image"]
    assert image_calls[0][2]["reference"] is not None