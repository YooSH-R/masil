"""분할 전 walk_log_pipeline.run() 과 새 payload_from_spec() 이
같은 요청을 만드는지 바이트 단위로 대조한다.

[왜 이렇게 검증하는가]
LLM 출력은 비결정적이라 결과물 비교로는 회귀를 잡을 수 없다.
검증 가능한 것은 "모델에게 전달되는 요청이 한 글자도 안 바뀌었다"이므로 그것만 본다.

[이미지를 변수에서 제거하는 이유]
imaging은 cv2 -> PIL 로 교체됐으므로 재압축된 프레임의 바이트는 반드시 달라진다.
그래서 레거시의 load_image_b64 를 고정값으로 몽키패치하고, 새 코드에도 같은
고정값을 넘긴다. 그러면 프롬프트/generationConfig/systemInstruction 배치/
merge 분기/few-shot 턴 순서가 정확히 일치하는지만 남는다.
이미지 인코더 자체는 test_imaging.py 에서 따로 검증한다.
"""

from __future__ import annotations

import importlib.util
import json
import sys
import types
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
LEGACY = ROOT / "legacy" / "legacy_walk_log_pipeline.py"

# 고정 이미지. 실제 인코딩 결과가 아니라 자리표시자다.
FAKE_IMAGE = ("QUJDRA==", "image/jpeg")


def _load_legacy():
    """레거시 파이프라인을 import한다.

    cv2는 스텁으로 대체한다(load_image_b64 를 몽키패치하므로 실제로 쓰이지 않는다).
    `import prompts` 는 새 패키지로 연결한다 - 두 패키지가 동일함은
    test_prompts.py 가 이미 증명했다.
    """
    if not LEGACY.exists():
        pytest.skip(f"레거시 파일이 없습니다: {LEGACY}")

    sys.modules.setdefault("cv2", types.ModuleType("cv2"))

    from walklog import prompts as new_prompts
    sys.modules["prompts"] = new_prompts

    import os
    os.environ.setdefault("GMS_KEY", "dummy-key-for-test")

    spec = importlib.util.spec_from_file_location("legacy_pipeline", LEGACY)
    module = importlib.util.module_from_spec(spec)
    sys.modules["legacy_pipeline"] = module
    spec.loader.exec_module(module)
    return module


class _FakeResponse:
    status_code = 200
    ok = True
    text = "{}"

    @staticmethod
    def raise_for_status() -> None:
        return None

    @staticmethod
    def json() -> dict:
        return {
            "candidates": [{"content": {"parts": [{"text": "ok"}]},
                            "finishReason": "STOP"}],
            "usageMetadata": {"promptTokenCount": 1, "candidatesTokenCount": 1,
                              "totalTokenCount": 2},
        }


@pytest.fixture(scope="module")
def legacy():
    module = _load_legacy()
    module.load_image_b64 = lambda path: FAKE_IMAGE
    return module


def legacy_payload(legacy_mod, spec, *, image: bool, system_mode: str,
                   use_schema: bool, **vars) -> dict:
    """레거시 run()이 requests.post에 넘기는 payload를 가로챈다."""
    captured: dict = {}

    def fake_post(url, headers=None, json=None, timeout=None):
        captured["url"] = url
        captured["payload"] = json
        return _FakeResponse()

    original_post = legacy_mod.requests.post
    original_mode = legacy_mod.SYSTEM_MODE
    original_schema = legacy_mod.USE_RESPONSE_SCHEMA
    try:
        legacy_mod.requests.post = fake_post
        legacy_mod.SYSTEM_MODE = system_mode
        legacy_mod.USE_RESPONSE_SCHEMA = use_schema
        legacy_mod.run(spec, image_path="dummy.jpg" if image else None, **vars)
    finally:
        legacy_mod.requests.post = original_post
        legacy_mod.SYSTEM_MODE = original_mode
        legacy_mod.USE_RESPONSE_SCHEMA = original_schema
    return captured["payload"]


def dumps(obj) -> str:
    """키 순서까지 비교하기 위해 sort_keys 없이 직렬화한다."""
    return json.dumps(obj, ensure_ascii=False, indent=1)


def assert_same(legacy_mod, spec, *, image=False, system_mode="system_instruction",
                use_schema=True, **vars):
    from walklog.gms import payload_from_spec

    old = legacy_payload(legacy_mod, spec, image=image, system_mode=system_mode,
                         use_schema=use_schema, **vars)
    new = payload_from_spec(
        spec,
        images=[FAKE_IMAGE] if image else [],
        system_mode=system_mode,
        use_schema=use_schema,
        **vars,
    )
    assert dumps(new) == dumps(old)


FRAME_VARS = dict(segment="seg_0000", elapsed="1분 30초",
                  shot_datetime="2026-07-29 08:12", location="불명")


@pytest.mark.parametrize("system_mode", ["system_instruction", "merge"])
@pytest.mark.parametrize("use_schema", [True, False])
def test_frame_extract_all_modes(legacy, system_mode, use_schema):
    """Stage 1: 이미지 + 스키마 + merge 분기 조합 4가지."""
    from walklog import prompts as P
    assert_same(legacy, P.FRAME_EXTRACT, image=True,
                system_mode=system_mode, use_schema=use_schema, **FRAME_VARS)


@pytest.mark.parametrize("style", ["plain", "emotional", "workout", "pet"])
def test_diary_all_styles(legacy, style):
    """Stage 2: 문체 프리셋 4종. 이미지 없음."""
    from walklog import prompts as P
    assert_same(legacy, P.diary_spec(style),
                walk_date="2026-07-29", duration="1분 47초", n_frames=11,
                json_lines='{"scene":"테스트"}')


def test_diary_merge_mode(legacy):
    from walklog import prompts as P
    assert_same(legacy, P.diary_spec("plain"), system_mode="merge",
                walk_date="2026-07-29", duration="1분 47초", n_frames=11,
                json_lines='{"scene":"테스트"}')


def test_image_prompt_writer(legacy):
    """Stage 3: 영어 프롬프트 작성기."""
    from walklog import prompts as P
    assert_same(legacy, P.IMAGE_PROMPT_WRITER,
                json_lines='{"scene":"테스트"}', focus="the most representative scene")


def test_story_image_writer_assembles():
    """STORY_IMAGE_WRITER: story + json_lines 두 변수만으로 KeyError 없이 조립된다.

    분할 전 파일에 없던 신규 스펙이라 legacy 대조 없이 조립 자체만 검증한다.
    """
    from walklog import prompts as P
    from walklog.gms import payload_from_spec

    body = payload_from_spec(
        P.STORY_IMAGE_WRITER,
        story="비 온 뒤 골목을 걸었다.",
        json_lines='{"scene":"테스트"}',
    )
    user_text = body["contents"][0]["parts"][0]["text"]
    assert "비 온 뒤 골목을 걸었다." in user_text
    assert '{"scene":"테스트"}' in user_text


def test_story_image_writer_missing_variable_raises():
    from walklog import prompts as P
    from walklog.gms import payload_from_spec

    with pytest.raises(KeyError):
        payload_from_spec(P.STORY_IMAGE_WRITER, story="이야기만 있음")


def test_story_image_verifier_assembles():
    """STORY_IMAGE_VERIFIER: json_lines 하나만으로 KeyError 없이 조립된다."""
    from walklog import prompts as P
    from walklog.gms import payload_from_spec

    body = payload_from_spec(
        P.STORY_IMAGE_VERIFIER,
        json_lines='{"scene":"테스트"}',
    )
    user_text = body["contents"][0]["parts"][0]["text"]
    assert '{"scene":"테스트"}' in user_text
    assert body["generationConfig"]["responseSchema"] == P.STORY_IMAGE_VERIFIER.response_schema
    assert "pass" in body["generationConfig"]["responseSchema"]["properties"]


def test_story_image_verifier_missing_variable_raises():
    from walklog import prompts as P
    from walklog.gms import payload_from_spec

    with pytest.raises(KeyError):
        payload_from_spec(P.STORY_IMAGE_VERIFIER)


def test_panel_caption_writer(legacy):
    from walklog import prompts as P
    assert_same(legacy, P.PANEL_CAPTION_WRITER, record_json='{"scene":"테스트"}')


def test_few_shot_turn_order(legacy):
    """few-shot 예시의 user/model 턴 순서.

    현재 스펙에는 examples가 없지만, 레거시 삽화 스크립트는 이 필드를 무시했다.
    나중에 예시를 붙였을 때 조용히 사라지지 않는지 지금 고정해 둔다.
    """
    from walklog import prompts as P
    spec = P.IMAGE_PROMPT_WRITER.tweak(
        examples=[("예시 입력 1", "예시 출력 1"), ("예시 입력 2", "예시 출력 2")]
    )
    assert_same(legacy, spec, json_lines="{}", focus="x")


def test_missing_variable_raises():
    """변수 누락은 즉시 실패해야 한다.

    레거시 삽화 스크립트는 경고만 하고 지시문을 버린 뒤 json_lines만 보냈다.
    결과물이 그럴듯하게 나와서 누락을 알아챌 수 없었다.
    """
    from walklog import prompts as P
    from walklog.gms import payload_from_spec

    with pytest.raises(KeyError):
        payload_from_spec(P.FRAME_EXTRACT, segment="seg_0000")


def test_bad_system_mode_raises():
    from walklog import prompts as P
    from walklog.config import ConfigError
    from walklog.gms import payload_from_spec

    with pytest.raises(ConfigError):
        payload_from_spec(P.PANEL_CAPTION_WRITER, system_mode="sysyem_instruction",
                          record_json="{}")


def test_frame_schema_includes_indoor_field():
    """실내 프레임 배제 기능의 기반 - indoor는 필수 필드여야 한다.

    누락되면 records.FrameRecord.is_indoor가 구형 기록으로 취급해 문자열
    추정으로 물러나므로, VLM이 매번 이 필드를 채워야 배제/대체 로직이 돈다.
    """
    from walklog import prompts as P

    assert "indoor" in P.FRAME_SCHEMA["properties"]
    assert P.FRAME_SCHEMA["properties"]["indoor"]["type"] == "BOOLEAN"
    assert "indoor" in P.FRAME_SCHEMA["required"]


def test_image_generation_config():
    """이미지 생성 요청은 responseModalities만 담는다."""
    from walklog.gms import build_payload

    body = build_payload(
        user_text="watercolor path",
        images=[FAKE_IMAGE],
        generation_config={"responseModalities": ["IMAGE"]},
    )
    assert body["generationConfig"] == {"responseModalities": ["IMAGE"]}
    assert "systemInstruction" not in body
    parts = body["contents"][0]["parts"]
    assert parts[0]["inlineData"]["mimeType"] == "image/jpeg"
    assert parts[-1]["text"] == "watercolor path"


def test_fingerprint_hides_base64():
    """덤프 시 base64가 지문으로 치환되는지."""
    from walklog.gms import build_payload, fingerprint_payload

    body = build_payload(user_text="t", images=[("A" * 5000, "image/jpeg")],
                         generation_config={})
    printed = json.dumps(fingerprint_payload(body), ensure_ascii=False)
    assert "A" * 100 not in printed
    assert "b64_chars=5000" in printed


# ------------------------------------------------------------ thinkingBudget

def test_thinking_budget_absent_by_default():
    """기본값 None이면 thinkingConfig 필드를 아예 넣지 않는다.

    프록시가 모르는 필드를 넣으면 400이 날 수 있으므로 명시적 opt-in이어야 한다.
    이 성질이 깨지면 분할 전과의 페이로드 동일성도 함께 깨진다.
    """
    from walklog import prompts as P
    from walklog.gms import spec_generation_config

    cfg = spec_generation_config(P.FRAME_EXTRACT, use_schema=True)
    assert "thinkingConfig" not in cfg
    assert P.FRAME_EXTRACT.thinking_budget is None


@pytest.mark.parametrize("budget", [0, 128])
def test_thinking_budget_emitted_when_set(budget):
    """켰을 때만 나가고, 값이 그대로 전달되는지.

    Stage 1은 저온 + 스키마 강제라 사고가 필요 없는데, 사고 토큰이
    max_output_tokens를 먼저 소진하면 JSON이 잘려 프레임이 버려진다.
    전략 문서의 'thinkingBudget: 0 또는 최소' 항목이 이 경로다.
    """
    from walklog import prompts as P
    from walklog.gms import spec_generation_config

    spec = P.FRAME_EXTRACT.tweak(thinking_budget=budget)
    cfg = spec_generation_config(spec, use_schema=True)
    assert cfg["thinkingConfig"] == {"thinkingBudget": budget}
    # 기존 키 순서는 유지된다(thinkingConfig가 뒤에 붙는다).
    assert list(cfg)[:2] == ["temperature", "maxOutputTokens"]