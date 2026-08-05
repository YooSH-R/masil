"""Stage 3 - LLM: 관찰 기록 -> 이미지 생성 모델용 프롬프트 + 스타일 조립.

관찰 기록(한국어) -> 이미지 모델용 프롬프트(영어)로 번역/재구성하는 단계.
대부분의 이미지 생성 모델은 영어 프롬프트에서 성능이 좋고,
한국어 서술문보다 쉼표로 나열된 키워드 구조에 더 잘 반응한다.

[작성기가 네 개인 이유]
  IMAGE_PROMPT_WRITER  : 한 장면을 한 장으로. 기본 삽화용.
  FLOW_IMAGE_WRITER    : 산책 전체를 한 장으로. "여러 장소를 합치지 말라"는 추가 제약 필요.
  STORY_IMAGE_WRITER   : Stage 2가 쓴 이야기의 감정적 핵심 장면을 한 장으로.
                         사실은 기록에서, 분위기는 이야기에서 가져온다.
  PANEL_CAPTION_WRITER : 스토리보드 칸 캡션. 한국어, 초단문.
규칙 목록이 일부 겹치지만, 스테이지별로 따로 튜닝되는 성질이므로
각자 전문을 들고 있게 둔다. 동기화가 필수인 개인정보 조항만 rules.py에서 온다.
"""

from __future__ import annotations

from . import rules
from .spec import PromptSpec

__all__ = [
    "IMAGE_PROMPT_WRITER",
    "FLOW_IMAGE_WRITER",
    "STORY_IMAGE_WRITER",
    "PANEL_CAPTION_WRITER",
    "IMAGE_STYLES",
    "DEFAULT_IMAGE_STYLE",
    "IMAGE_NEGATIVE",
    "IMAGE_SUFFIX",
    "build_image_prompt",
    "build_image_request",
]


# ------------------------------------------------------------ 프롬프트 작성기

IMAGE_PROMPT_WRITER = PromptSpec(
    system="""\
You are a prompt engineer for text-to-image models.
You receive Korean observation records from a walk, and write ONE image prompt in English.

Rules:
1. Use only elements present in the records. Do not invent landmarks or objects.
2. Output a comma-separated keyword sequence, not a sentence.
   Order: subject/scene, environment, time of day, weather, season, mood, composition.
3. <<PRIVACY_EN>>
4. Keep it under 60 words. Do not add style or quality keywords - those are appended separately.
5. Output the prompt only. No explanation, no quotes, no markdown.
""".replace("<<PRIVACY_EN>>", rules.PRIVACY_EN),
    user_template="""\
[Walk observation records]
{json_lines}

[Requested focus]
{focus}

Write one English image prompt describing the most representative scene of this walk.\
""",
    temperature=0.6,
    # 60단어 프롬프트 자체는 100토큰이면 되지만, thinking 모델은 사고 토큰을
    # 먼저 쓴다. 예산이 빡빡하면 사고 도중에 소진되어 finishReason=MAX_TOKENS로
    # 응답이 비어 온다. max_output_tokens는 상한일 뿐 실제 생성량만 과금되므로
    # 넉넉히 두는 편이 손해가 없다.
    max_output_tokens=4096,
)

# generate_flow_image.py --mode single 전용: 산책 전체(여러 프레임)를 한 장으로
# 요약하는 프롬프트. IMAGE_PROMPT_WRITER와 달리 "여러 장면을 하나로 합치지 말라"는
# 지시가 필요하다 - 안 그러면 서로 다른 장소가 뒤섞인 불가능한 풍경이 나온다.
FLOW_IMAGE_WRITER = PromptSpec(
    system="""\
You are a prompt engineer for text-to-image models.
You receive Korean observation records from an ENTIRE walk (multiple frames,
time-ordered) and write ONE image prompt in English summarizing its flow.

Rules:
1. Use only elements present in the records. Do not invent landmarks or objects.
2. Do NOT merge every location into one impossible landscape. Choose the single
   most representative scene and let the other records influence only lighting,
   weather, season and mood.
3. Prefer a wide horizontal composition suggesting a path continuing forward.
4. Output a comma-separated keyword sequence, not a sentence.
   Order: subject/scene, environment, time of day, weather, season, mood, composition.
5. <<PRIVACY_EN>>
6. Keep it under 60 words. Do not add style or quality keywords - those are appended separately.
7. Output the prompt only. No explanation, no quotes, no markdown.
""".replace("<<PRIVACY_EN>>", rules.PRIVACY_EN),
    user_template="""\
[Walk overview]
- Date: {walk_date}
- Duration: {duration}
- Representative scenes: {n_scenes}

[Walk observation records (time-ordered)]
{json_lines}

Write one English image prompt summarizing this walk's overall flow as a single scene.\
""",
    temperature=0.6,
    max_output_tokens=4096,   # 위와 같은 이유
)

# 이야기(Stage 2 산출물)의 감정적 핵심 장면을 한 장으로. 사실은 records에서,
# 분위기는 story에서 가져온다. story만 주면 LLM이 기록에 없는 사물을
# 이야기의 수사에서 끌어와 그리므로, 두 입력을 함께 준다.
STORY_IMAGE_WRITER = PromptSpec(
    system="""\
You are a prompt engineer for text-to-image models.
You receive (a) a short Korean story written about a walk, and
(b) the factual observation records that story was based on.
Write ONE image prompt in English capturing the story's emotional core.

Rules:
1. Physical elements (objects, location, weather, time) must come from the
   records only. Do not invent objects, even ones implied by the story.
2. Mood, lighting emphasis, and atmosphere should come from the story --
   especially its final scene, which carries the emotional weight.
3. One single scene. Do not merge multiple locations.
4. <<PRIVACY_EN>>
5. Output a comma-separated keyword sequence, not a sentence.
   Order: subject/scene, environment, time of day, weather, season, mood, composition.
6. Keep it under 60 words. Do not add style or quality keywords.
7. Output the prompt only. No explanation, no quotes, no markdown.
""".replace("<<PRIVACY_EN>>", rules.PRIVACY_EN),
    user_template="""\
[Story (Korean)]
{story}

[Factual observation records (time-ordered)]
{json_lines}

Write one English image prompt for the emotional key scene of this story.\
""",
    temperature=0.7,
    max_output_tokens=4096,   # thinking 토큰 여유분. 다른 작성기와 같은 이유.
)

# generate_flow_image.py 스토리보드 각 칸에 붙는 짧은 한국어 캡션.
PANEL_CAPTION_WRITER = PromptSpec(
    system="""\
너는 산책 스토리보드의 칸 캡션을 쓰는 편집자다.
기록에 있는 요소만 써서 12자 이내의 명사구 한 개만 출력한다.
문장부호, 설명, 따옴표를 쓰지 않는다. 상호명과 사람의 외모는 쓰지 않는다.
""",
    user_template="""\
[이 장면의 관찰 기록]
{record_json}

이 장면을 대표하는 12자 이내 명사구 캡션을 하나만 출력해라.\
""",
    temperature=0.4,
    # 12자 캡션에 64토큰이면 충분해 보이지만, 사고 토큰이 그 64를 먼저 소진해
    # 응답이 비어 오는 사고가 실제로 발생했다(삽화 3장을 만든 뒤 캡션에서 중단).
    # 사고량은 호출마다 달라서 어떤 칸은 통과하고 어떤 칸은 실패한다.
    max_output_tokens=4096,
)


# ------------------------------------------------------------ 스타일 / 조립

# 스타일을 추가하려면 여기에 항목만 넣으면 된다.
IMAGE_STYLES: dict[str, str] = {
    "watercolor": "soft watercolor illustration, gentle washes, subtle paper grain "
                  "across the whole image, muted palette, hand-painted feel",
    "storybook": "children's storybook illustration, warm flat colors, "
                 "simple rounded shapes, gentle outlines",
    "lineart": "minimal ink line art, monochrome, clean thin strokes, generous white space",
    "photoreal": "photorealistic, natural lighting, 35mm lens, shallow depth of field",
    "pixel": "16-bit pixel art, limited palette, crisp dithering, isometric view",
}

DEFAULT_IMAGE_STYLE = "watercolor"

IMAGE_NEGATIVE = (
    "text, watermark, signature, logo, brand name, license plate, "
    "recognizable faces, portrait, distorted anatomy, extra limbs, "
    "oversaturated, cluttered, lowres, jpeg artifacts, "
    "white borders, paper edges, frame, margins, matting"
)

# 최종 조립 순서: 장면 프롬프트 -> 스타일 -> 공통 접미어
IMAGE_SUFFIX = "no text, no watermark, full-bleed composition, the artwork fills the entire canvas edge-to-edge"


def build_image_prompt(
    scene_prompt: str,
    style: str = DEFAULT_IMAGE_STYLE,
    extra: str = "",
) -> dict[str, str]:
    """장면 프롬프트에 스타일을 붙여 이미지 모델 입력으로 조립.

    반환 형태는 모델에 무관한 dict이므로,
    호출부에서 각 이미지 API의 필드명(prompt / negative_prompt 등)에 매핑한다.
    """
    if style not in IMAGE_STYLES:
        raise KeyError(f"등록되지 않은 이미지 스타일: {style} (사용 가능: {list(IMAGE_STYLES)})")
    parts = [scene_prompt.strip().rstrip(","), IMAGE_STYLES[style]]
    if extra:
        parts.append(extra.strip())
    parts.append(IMAGE_SUFFIX)
    return {
        "prompt": ", ".join(p for p in parts if p),
        "negative_prompt": IMAGE_NEGATIVE,
    }


# ------------------------------------------------------------ Gemini 전용 어댑터

# Gemini 이미지 API에는 negative_prompt 필드가 없다. 그래서 부정 조건을
# 본문에 서술형으로 녹여야 하는데, 그 문구가 실행 코드에 있으면
# 프롬프트 관리 지점이 두 곳으로 쪼개진다.
# (분할 전 generate_flow_image.py 의 compose_prompt 안에 이 문장들이 숨어 있었다)
_NEGATIVE_LINE = "Do not include any of the following: {negative}."
_OUTPUT_RULE = "Output the illustration only, with no caption or text in the image."


def build_image_request(
    scene_prompt: str,
    style: str = DEFAULT_IMAGE_STYLE,
    extra: str = "",
) -> str:
    """이미지 모델에 실제로 보낼 최종 프롬프트 문자열.

    build_image_prompt()는 모델에 무관한 dict를 돌려준다(negative_prompt 필드를
    지원하는 다른 이미지 API에 붙일 때 그 형태가 유효하다).
    이 함수는 그 위에 얹는 Gemini 전용 어댑터로, 부정 조건을 본문에 합친다.
    """
    parts = build_image_prompt(scene_prompt, style=style, extra=extra)
    return "\n\n".join([
        parts["prompt"],
        _NEGATIVE_LINE.format(negative=parts["negative_prompt"]),
        _OUTPUT_RULE,
    ])