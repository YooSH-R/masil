"""walklog/prompts/image.py의 build_image_prompt / build_image_request 검증.

무게중심: 화풍 드리프트(watercolor 지정에도 간헐적으로 사진풍이 나오는 문제)를
막는 세 가지 방어선이 실제로 조립되는지.
  1. photoreal이 아닌 스타일에는 반사진 부정 조건이 들어간다.
  2. 참조 이미지를 쓸 때는 "구도만 빌리고 화풍은 다시 그려라" 지시가 들어간다.
  3. 스타일이 장면 키워드보다 먼저 나온다(뒤에 있으면 묻힌다).
photoreal 스타일은 반대로 두 방어선 모두 빠져야 한다 - 사진풍이 그 스타일의 목적이다.
"""

from __future__ import annotations

import pytest

from walklog import prompts as P
from walklog.prompts.image import (
    ANTI_PHOTO_NEGATIVE,
    IMAGE_NEGATIVE,
    IMAGE_STYLES,
    PHOTO_STYLES,
    build_image_prompt,
    build_image_request,
)


# ------------------------------------------------------------ 반사진 부정 조건

@pytest.mark.parametrize("style", [s for s in IMAGE_STYLES if s not in PHOTO_STYLES])
def test_non_photo_styles_get_anti_photo_negative(style):
    result = build_image_prompt("a quiet path", style=style)
    assert "photorealistic" in result["negative_prompt"]
    assert ANTI_PHOTO_NEGATIVE in result["negative_prompt"]


def test_photoreal_style_has_no_anti_photo_negative():
    result = build_image_prompt("a quiet path", style="photoreal")
    assert "photorealistic" not in result["negative_prompt"]
    assert result["negative_prompt"] == IMAGE_NEGATIVE


def test_anti_photo_negative_does_not_replace_base_negative():
    """기존 IMAGE_NEGATIVE 항목(여백 방지 등)이 사라지지 않는지."""
    result = build_image_prompt("a quiet path", style="watercolor")
    for item in ("white borders", "paper edges", "text", "watermark"):
        assert item in result["negative_prompt"]


# ------------------------------------------------------------ 참조 재해석 지시

def test_with_reference_true_adds_repaint_instruction():
    prompt = build_image_request("a quiet path", style="watercolor", with_reference=True)
    assert "Completely repaint it" in prompt
    assert "ONLY for composition" in prompt


def test_with_reference_false_omits_repaint_instruction():
    prompt = build_image_request("a quiet path", style="watercolor", with_reference=False)
    assert "Completely repaint it" not in prompt


def test_with_reference_default_is_false():
    """기존 호출부와의 호환을 위해 기본값은 False다."""
    prompt = build_image_request("a quiet path", style="watercolor")
    assert "Completely repaint it" not in prompt


def test_photoreal_style_omits_repaint_instruction_even_with_reference():
    """photoreal은 사진풍이 목적이므로 참조를 재해석하라는 지시가 오히려 해롭다."""
    prompt = build_image_request("a quiet path", style="photoreal", with_reference=True)
    assert "Completely repaint it" not in prompt


# ------------------------------------------------------------ 조립 순서

def test_style_label_comes_before_scene():
    result = build_image_prompt("a quiet path", style="watercolor")
    prompt = result["prompt"]
    assert "Art style" in prompt and "Scene:" in prompt
    assert prompt.index("Art style") < prompt.index("Scene:")


def test_style_label_precedes_scene_in_final_request_too():
    prompt = build_image_request("a quiet path", style="watercolor")
    assert prompt.index("Art style") < prompt.index("Scene:")


def test_scene_prompt_content_still_present():
    """조립 순서가 바뀌어도 장면 키워드 자체는 그대로 실린다."""
    result = build_image_prompt("golden retriever chasing leaves", style="lineart")
    assert "golden retriever chasing leaves" in result["prompt"]


def test_extra_still_appended_after_scene():
    result = build_image_prompt("a quiet path", style="lineart", extra="wide shot")
    assert "wide shot" in result["prompt"]
    assert result["prompt"].index("Scene:") < result["prompt"].index("wide shot")


# ------------------------------------------------------------ 패키지 재수출

def test_photo_styles_and_anti_photo_negative_exported_from_package():
    assert P.PHOTO_STYLES == {"photoreal"}
    assert P.ANTI_PHOTO_NEGATIVE == ANTI_PHOTO_NEGATIVE


# ------------------------------------------------------------ 인물 배제 (개인정보)
# 2026-08-05 session3 event_02: "silhouette of a person's head" 서술이
# 얼굴(눈/눈썹)로 승격됐다. 완화 서술(먼 실루엣) 대신 전면 배제로 바꾼
# rules.PRIVACY_EN이 실제로 작성기 system과 참조 재해석 지시 양쪽에
# 반영되는지 확인한다 - 한쪽만 배제하면 다른 경로(참조 사진)로 인물이
# 다시 들어온다.

def test_privacy_en_excludes_people_entirely():
    from walklog.prompts import rules
    assert "omit them from the scene entirely" in rules.PRIVACY_EN
    assert "no person were present" in rules.PRIVACY_EN


@pytest.mark.parametrize("writer", [
    P.IMAGE_PROMPT_WRITER, P.FLOW_IMAGE_WRITER, P.STORY_IMAGE_WRITER,
])
def test_writers_using_privacy_en_include_people_exclusion(writer):
    """PRIVACY_EN을 참조하는 작성기(IMAGE_PROMPT_WRITER/FLOW_IMAGE_WRITER/
    STORY_IMAGE_WRITER)의 system에 인물 전면 배제 문구가 실제로 반영됐는지."""
    assert "omit them from the scene entirely" in writer.system


def test_reference_rule_excludes_people_from_reference_photo():
    """장면 프롬프트에서 인물을 지워도 참조 사진에는 남아 있으므로,
    참조 재해석 지시(_REFERENCE_RULE) 안에서도 별도로 인물을 빼라고 닫는다."""
    prompt = build_image_request("a quiet path", style="watercolor", with_reference=True)
    assert "leave them out of the artwork entirely" in prompt


def test_reference_rule_people_exclusion_absent_without_reference():
    prompt = build_image_request("a quiet path", style="watercolor", with_reference=False)
    assert "leave them out of the artwork entirely" not in prompt


# ------------------------------------------------------------ 화풍 검사 스키마 강화

def test_style_check_schema_requires_face_visible():
    """혼종 판정(matches_style)과 인물 노출(face_visible) 모두 필수 필드다."""
    schema = P.PANEL_STYLE_CHECKER.response_schema
    for field in ("is_photographic", "matches_style", "face_visible"):
        assert field in schema["properties"]
        assert field in schema["required"]
