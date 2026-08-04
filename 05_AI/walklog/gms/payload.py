"""PromptSpec -> Gemini 요청 dict 조립.

[이 파일의 성질]
네트워크도 파일 시스템도 이미지 라이브러리도 모른다. 순수 함수만 있다.
그래서 API 키 없이, 사진 없이 "어떤 요청을 보낼 것인가"를 전부 검증할 수 있다.
프롬프트 리팩터링의 회귀 검증이 여기에 걸린다.

[두 층으로 나눈 이유]
  build_payload      : 이미 렌더링된 문자열을 받는 저수준 조립기
  payload_from_spec  : PromptSpec을 렌더링해 위 함수에 넘기는 고수준 조립기

삽화 생성은 build_image_request()가 만든 완성된 프롬프트를 그대로 보내야 한다.
그걸 PromptSpec으로 감싸면 render()가 .format()을 호출해서 프롬프트 안의
중괄호가 터진다. 저수준 층이 따로 있으면 그 경로를 우회한다.

[표기 통일]
분할 전 두 호출부가 inlineData(camelCase)와 inline_data(snake_case)를 섞어 썼다.
Gemini REST의 정식 표기이자 응답에서 돌아오는 형태인 camelCase로 통일한다.
"""

from __future__ import annotations

import hashlib
import json
from typing import Any, NamedTuple, Sequence

from .. import config
from ..prompts import PromptSpec

__all__ = [
    "InlineImage",
    "MODALITY_IMAGE",
    "IMAGE_GENERATION_CONFIG",
    "spec_generation_config",
    "build_payload",
    "payload_from_spec",
    "fingerprint_payload",
]


class InlineImage(NamedTuple):
    """인라인 전송용 이미지. (b64, mime) 튜플과 호환된다."""

    b64: str
    mime: str


MODALITY_IMAGE = "IMAGE"

# 이미지 모델은 이 설정이 없으면 텍스트 설명만 돌려준다.
# temperature나 maxOutputTokens는 넣지 않는다(이미지 생성에 의미가 없다).
IMAGE_GENERATION_CONFIG: dict[str, Any] = {"responseModalities": [MODALITY_IMAGE]}


def spec_generation_config(spec: PromptSpec, *, use_schema: bool) -> dict[str, Any]:
    """PromptSpec의 생성 파라미터를 Gemini generationConfig로 변환.

    키 순서를 분할 전과 동일하게 유지한다. 페이로드를 바이트 단위로 대조해
    회귀를 검증하기 때문이다.
    """
    cfg: dict[str, Any] = {
        "temperature": spec.temperature,
        "maxOutputTokens": spec.max_output_tokens,
    }
    if spec.response_schema is not None and use_schema:
        cfg["responseMimeType"] = "application/json"
        cfg["responseSchema"] = spec.response_schema
    # thinking_budget이 None이면 필드를 아예 넣지 않는다.
    # 넣는 순간 프록시가 모르는 필드로 400을 낼 수 있으므로 명시적 opt-in이다.
    if spec.thinking_budget is not None:
        cfg["thinkingConfig"] = {"thinkingBudget": spec.thinking_budget}
    return cfg


def build_payload(
    *,
    user_text: str,
    system: str | None = None,
    images: Sequence[tuple[str, str]] = (),
    examples: Sequence[tuple[str, str]] = (),
    generation_config: dict[str, Any],
) -> dict[str, Any]:
    """저수준 조립기. user_text는 이미 렌더링이 끝난 문자열이어야 한다.

    system을 주면 systemInstruction 필드로 나간다.
    merge 모드처리는 호출부(payload_from_spec)가 미리 user_text에 합쳐서 넘긴다.
    """
    contents: list[dict[str, Any]] = []

    # few-shot 예시. 비어 있으면 건너뛴다.
    for user_example, model_example in examples:
        contents.append({"role": "user", "parts": [{"text": user_example}]})
        contents.append({"role": "model", "parts": [{"text": model_example}]})

    parts: list[dict[str, Any]] = []
    # 이미지를 텍스트보다 먼저 넣는다: "이 이미지를 보고 ~" 의미가 된다.
    for b64, mime in images:
        parts.append({"inlineData": {"mimeType": mime, "data": b64}})
    parts.append({"text": user_text})
    contents.append({"role": "user", "parts": parts})

    payload: dict[str, Any] = {
        "contents": contents,
        "generationConfig": generation_config,
    }
    if system:
        payload["systemInstruction"] = {"parts": [{"text": system}]}
    return payload


def payload_from_spec(
    spec: PromptSpec,
    *,
    images: Sequence[tuple[str, str]] = (),
    system_mode: str = config.SYSTEM_MODE,
    use_schema: bool = config.USE_RESPONSE_SCHEMA,
    **vars: Any,
) -> dict[str, Any]:
    """PromptSpec을 렌더링해 요청 dict로 만든다.

    render()가 KeyError를 내면 그대로 올린다. 분할 전 삽화 스크립트는 여기서
    경고만 하고 지시문을 통째로 버린 뒤 json_lines만 보냈는데, 결과물이
    그럴듯하게 나와서 누락을 알아챌 수 없었다. 변수 누락은 버그이므로 즉시 실패한다.
    """
    config.check_system_mode(system_mode)

    user_text = spec.render(**vars)
    system = spec.system

    if system_mode == "merge" and system:
        # 이미지 다음에 놓이므로 user_template의 "위 이미지" 지시가 그대로 유효하다.
        user_text = f"{system}\n\n---\n\n{user_text}"
        system = None

    gen_config = spec_generation_config(spec, use_schema=use_schema)

    return build_payload(
        user_text=user_text,
        system=system,
        images=images,
        examples=spec.examples,
        generation_config=gen_config,
    )


def fingerprint_payload(payload: dict[str, Any]) -> dict[str, Any]:
    """base64 이미지 데이터를 지문으로 치환한 사본을 반환한다.

    페이로드를 그대로 덤프하면 수십 KB짜리 한 줄이 되어 diff가 무의미해지고
    저장소도 부풀어 오른다. 지문으로 바꾸면 "같은 이미지가 같은 방식으로
    인코딩됐다"는 사실은 검증되면서 파일은 읽을 수 있는 크기로 남는다.
    """
    clone = json.loads(json.dumps(payload, ensure_ascii=False))
    for content in clone.get("contents", []):
        for part in content.get("parts", []):
            blob = part.get("inlineData")
            if isinstance(blob, dict) and isinstance(blob.get("data"), str):
                data = blob["data"]
                digest = hashlib.sha256(data.encode("ascii")).hexdigest()[:12]
                blob["data"] = f"<sha256:{digest} b64_chars={len(data)}>"
    return clone