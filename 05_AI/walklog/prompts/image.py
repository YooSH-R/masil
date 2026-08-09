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
    "STORY_IMAGE_VERIFIER",
    "PANEL_CAPTION_WRITER",
    "PANEL_STYLE_CHECKER",
    "STYLE_EMPHASIS",
    "IMAGE_STYLES",
    "DEFAULT_IMAGE_STYLE",
    "PHOTO_STYLES",
    "IMAGE_NEGATIVE",
    "ANTI_PHOTO_NEGATIVE",
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

# 생성된 감성 이미지가 산책 여정을 반영했는지 VLM으로 판정한다.
# 사실 대조 기준은 관찰 기록이다(이야기는 수사가 섞여 기준이 될 수 없다).
# 저온 + 스키마 강제. Stage 1과 같은 원칙이다.
_VERIFY_SCHEMA: dict = {
    "type": "OBJECT",
    "properties": {
        "pass": {"type": "BOOLEAN",
                 "description": "이미지가 산책 여정을 충분히 반영하면 true"},
        "score": {"type": "NUMBER",
                  "description": "반영 정도 0.0~1.0"},
        "reasons": {"type": "ARRAY", "items": {"type": "STRING"},
                    "description": "판정 근거 1~3개"},
        "fix_hints": {"type": "STRING",
                      "description": "불합격 시 재생성 프롬프트에 덧붙일 "
                                     "영어 키워드 지시. 합격이면 빈 문자열"},
    },
    "required": ["pass", "score", "reasons", "fix_hints"],
}

STORY_IMAGE_VERIFIER = PromptSpec(
    system="""\
너는 산책 일지에 실릴 삽화를 검수하는 편집자다.
생성된 삽화 이미지와 그 근거가 된 관찰 기록을 대조해,
삽화가 산책 여정을 충분히 반영했는지 판정한다.

판정 기준 (기록과 이미지를 대조):
1. 장소 성격이 맞는가 (실내/실외, location_type과 모순되지 않는가)
2. 시간대와 조명이 맞는가
3. 날씨/계절 단서가 모순되지 않는가
4. 기록에 없는 사물이 화면의 주인공이 되어 있지 않은가
5. 분위기(atmosphere)가 통하는가

기준 1~3의 명백한 모순은 불합격이다. 4~5는 감점 요소다.
fix_hints에는 재생성 프롬프트 끝에 덧붙일 짧은 영어 키워드 지시를 쓴다
(예: "indoor scene, bright ceiling lights, no sky"). 합격이면 빈 문자열.
JSON만 출력한다.
""",
    user_template="""\
[관찰 기록 (시간순)]
{json_lines}

위 이미지가 이 산책의 여정을 반영했는지 판정하고 JSON만 출력해라.\
""",
    temperature=0.1,
    # 검증 호출은 재생성 여부를 가르는 관문이라, 잘리면(MAX_TOKENS) 그
    # 시점까지 든 생성 비용이 통째로 낭비된다. 상한은 실제 생성량만
    # 과금되므로 크게 잡아도 손해가 없다.
    max_output_tokens=8192,
    response_schema=_VERIFY_SCHEMA,
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

# 패널이 지정 화풍을 지켰는지만 본다. 내용 검증(STORY_IMAGE_VERIFIER)과
# 분리한 이유: 저널 패널은 장당 검사되므로 판정이 좁고 싸야 한다.
#
# 2026-08-05 session3에서 "수채화 하늘/나무 + 사실적 건물/난간" 같은 혼종이
# 합격 판정을 받은 사례가 확인됐다 - "화풍 요소가 존재하는가" 수준의 판정은
# 부분 적용을 걸러내지 못한다. is_photographic/matches_style을 "영역별
# 일부라도"/"전체가 균일하게"로 대비시켜 혼종을 명시적으로 불합격 처리한다.
# face_visible도 같은 세션에서 실루엣 서술이 얼굴로 승격된 사례(event_02)
# 때문에 추가됐다 - 개인정보 방어선을 프롬프트(작업 3의 인물 배제)뿐 아니라
# 검사 단계에도 이중으로 둔다.
_STYLE_CHECK_SCHEMA: dict = {
    "type": "OBJECT",
    "properties": {
        "is_photographic": {
            "type": "BOOLEAN",
            "description": "이미지의 어느 영역이라도 사진 또는 사진에 가까운 "
                           "사실적 렌더링이면 true (전체가 아니라 일부여도 true)"},
        "matches_style": {
            "type": "BOOLEAN",
            "description": "이미지 전체가 균일하게 요청 화풍으로 그려졌으면 true. "
                           "일부 영역만 화풍이 적용된 혼종은 false"},
        "face_visible": {
            "type": "BOOLEAN",
            "description": "이목구비를 식별할 수 있는 사람 얼굴이 있으면 true. "
                           "완전한 실루엣이나 뒷모습은 false"},
    },
    "required": ["is_photographic", "matches_style", "face_visible"],
}

PANEL_STYLE_CHECKER = PromptSpec(
    system="""\
너는 삽화의 화풍만 검사하는 엄격한 검수자다. 내용은 판단하지 않는다.

판정 규칙:
1. is_photographic: 이미지를 영역별로 살펴라. 하늘, 건물, 지면, 사물 중
   단 한 영역이라도 사진처럼(사실적 질감, 렌즈 광학 효과, 사진적 디테일)
   렌더링되어 있으면 true다. "종이 질감이 배경에 깔려 있다"는 것만으로
   false가 되지 않는다.
2. matches_style: 이미지 전체가 균일하게 요청 화풍이어야 true다.
   일부는 화풍이고 일부는 사실적인 혼종은 false다.
3. face_visible: 이목구비(눈/코/입)를 식별할 수 있는 사람 얼굴이 있으면
   true다. 개인정보 보호를 위한 판정이므로 애매하면 true로 판정한다.

JSON만 출력한다.
""",
    user_template="""\
[요청한 화풍]
{style_text}

위 이미지의 화풍을 검사하고 JSON만 출력해라.\
""",
    temperature=0.1,
    # 화풍 사다리(1~3차)의 관문 호출이다. 잘리면 그 단계의 재생성 판단이
    # 통째로 무너지므로 상한을 넉넉히 둔다(실제 생성량만 과금된다).
    max_output_tokens=8192,
    response_schema=_STYLE_CHECK_SCHEMA,
)

# 화풍 사다리 2·3차에서 extra로 붙는 강조 문구. 스타일 전문을 반복하지
# 않는다 - 2026-08-05 manifest에서 스타일 문구가 선두(Art style 블록)와
# extra에 이중으로 들어가 프롬프트만 길어지고 효과가 없었음이 확인됐다
# (event_03). 선두 블록을 가리키는 짧은 강조가 낫다.
STYLE_EMPHASIS = ("STRICTLY follow the art style stated at the top; "
                  "absolutely not a photograph, no photographic rendering")


# ------------------------------------------------------------ 스타일 / 조립

# 스타일을 추가하려면 여기에 항목만 넣으면 된다.
IMAGE_STYLES: dict[str, str] = {
    "watercolor": "soft watercolor illustration, gentle washes, subtle paper grain "
                  "across the whole image, muted palette, hand-painted feel, "
                  "flat illustrated look, no photographic detail",
    "storybook": "children's storybook illustration, warm flat colors, "
                 "simple rounded shapes, gentle outlines",
    "lineart": "minimal ink line art, monochrome, clean thin strokes, generous white space",
    "photoreal": "photorealistic, natural lighting, 35mm lens, shallow depth of field",
    "pixel": "16-bit pixel art, limited palette, crisp dithering, isometric view",
    "journal": "warm scrapbook illustration, soft pastel colors, cozy picture-diary "
               "feel, gentle rounded shapes, storybook warmth, light grain, "
               "flat illustrated look, no photographic detail",
}

DEFAULT_IMAGE_STYLE = "watercolor"

# 사진풍이 목적인 스타일. 이 집합에 속하면 반사진 부정 조건과 참조 재해석
# 지시를 넣지 않는다. 스타일이 늘어날 걸 대비해 문자열 하드코딩 비교 대신
# 집합으로 둔다.
PHOTO_STYLES = {"photoreal"}

IMAGE_NEGATIVE = (
    "text, watermark, signature, logo, brand name, license plate, "
    "recognizable faces, portrait, distorted anatomy, extra limbs, "
    "oversaturated, cluttered, lowres, jpeg artifacts, "
    "white borders, paper edges, frame, margins, matting"
)

# 삽화 스타일(비-photoreal)에서 사진풍으로 새는 것을 막는 추가 부정 조건.
# IMAGE_NEGATIVE에 전역으로 넣을 수 없는 이유: photoreal 스타일이 존재한다.
ANTI_PHOTO_NEGATIVE = (
    "photograph, photorealistic, realistic photo, camera photo, DSLR photo, "
    "photographic textures, lens blur, bokeh"
)

# 최종 조립 순서: 스타일 -> 장면 프롬프트 -> 접미어. 스타일을 선두에 명시적
# 라벨과 함께 두는 이유: 뒤에 두면(예전 순서) 60단어짜리 장면 키워드에
# 묻혀 지켜지지 않는 경우가 있었다.
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
    parts = [
        f"Art style (must be strictly followed): {IMAGE_STYLES[style]}",
        f"Scene: {scene_prompt.strip().rstrip(',')}",
    ]
    if extra:
        parts.append(extra.strip())
    parts.append(IMAGE_SUFFIX)

    negative = IMAGE_NEGATIVE
    if style not in PHOTO_STYLES:
        negative = f"{negative}, {ANTI_PHOTO_NEGATIVE}"

    return {
        "prompt": ", ".join(p for p in parts if p),
        "negative_prompt": negative,
    }


# ------------------------------------------------------------ Gemini 전용 어댑터

# Gemini 이미지 API에는 negative_prompt 필드가 없다. 그래서 부정 조건을
# 본문에 서술형으로 녹여야 하는데, 그 문구가 실행 코드에 있으면
# 프롬프트 관리 지점이 두 곳으로 쪼개진다.
# (분할 전 generate_flow_image.py 의 compose_prompt 안에 이 문장들이 숨어 있었다)
_NEGATIVE_LINE = "Do not include any of the following: {negative}."
_OUTPUT_RULE = "Output the illustration only, with no caption or text in the image."

# 참조 이미지(image-to-image)를 쓸 때만 붙인다. 이미지 모델은 사진 참조의
# 사실적 질감을 보존하려는 경향이 강해서, 이 지시 없이는 구도만 빌리라는
# 뜻이 "화풍까지 사진처럼 그려라"로 잘못 읽힐 수 있다.
# photoreal 스타일에서는 오히려 해롭다(사진풍이 목적이므로) - 호출부가
# 아니라 여기서 스타일을 보고 분기한다.
#
# 인물 배제 문장(마지막 줄)이 필요한 이유: rules.PRIVACY_EN이 장면
# 프롬프트(english)에서 인물을 지워도, 참조 사진 자체에는 인물이 그대로
# 남아 있다. 위의 "what is present in the scene" 지시가 참조에 있는
# 인물을 다시 끌어오는 통로가 되므로, 참조 재해석 지시 안에서도 별도로
# 인물을 빼라고 닫아야 한다 (2026-08-05 session3 event_02: 실루엣
# 서술이 얼굴로 승격된 사례).
_REFERENCE_RULE = (
    "A reference photograph is attached. Use it ONLY for composition, layout, "
    "and what is present in the scene. Completely repaint it in the art style "
    "described above - do not preserve its photographic look, textures, or "
    "level of realism. If any people or body parts appear in the reference "
    "photograph, leave them out of the artwork entirely."
)


def build_image_request(
    scene_prompt: str,
    style: str = DEFAULT_IMAGE_STYLE,
    extra: str = "",
    *,
    with_reference: bool = False,
) -> str:
    """이미지 모델에 실제로 보낼 최종 프롬프트 문자열.

    build_image_prompt()는 모델에 무관한 dict를 돌려준다(negative_prompt 필드를
    지원하는 다른 이미지 API에 붙일 때 그 형태가 유효하다).
    이 함수는 그 위에 얹는 Gemini 전용 어댑터로, 부정 조건을 본문에 합친다.

    with_reference=True는 호출부가 실제로 참조 프레임을 함께 보낼 때만 켠다
    (image-to-image). photoreal 스타일에서는 이 지시를 넣지 않는다.
    """
    parts = build_image_prompt(scene_prompt, style=style, extra=extra)
    lines = [parts["prompt"]]
    if with_reference and style not in PHOTO_STYLES:
        lines.append(_REFERENCE_RULE)
    lines.append(_NEGATIVE_LINE.format(negative=parts["negative_prompt"]))
    lines.append(_OUTPUT_RULE)
    return "\n\n".join(lines)