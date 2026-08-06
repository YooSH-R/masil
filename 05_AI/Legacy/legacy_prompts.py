"""프롬프트 중앙 관리 모듈.

AI의 동작을 바꾸고 싶으면 이 파일만 수정하면 된다.
실행 로직(API 호출, 이미지 압축, 파일 I/O)은 이 파일에 두지 않는다.

[구성]
  0. 공통 - PromptSpec 정의
  1. VLM  - 프레임 관찰 기록 추출
  2. LLM  - 산책 일지 작성 (+ 문체 프리셋)
  3. LLM  - 이미지 생성 프롬프트 작성기
  4. 이미지 생성 - 스타일 프리셋 / 네거티브 프롬프트
  5. 레지스트리

[주의]
  system 문자열에는 출력 예시용 중괄호가 들어 있으므로 .format()을 쓰지 않는다.
  변수를 꽂아야 할 때는 <<NAME>> 형태의 센티널을 쓰고 replace로 치환한다.
  user_template에는 중괄호가 없으므로 .format()을 그대로 쓴다.
"""

from __future__ import annotations

from dataclasses import dataclass, field, replace

__all__ = [
    "PromptSpec",
    "FRAME_EXTRACT",
    "FRAME_SCHEMA",
    "DIARY_STYLES",
    "diary_spec",
    "IMAGE_PROMPT_WRITER",
    "FLOW_IMAGE_WRITER",
    "PANEL_CAPTION_WRITER",
    "IMAGE_STYLES",
    "IMAGE_NEGATIVE",
    "build_image_prompt",
    "REGISTRY",
    "get",
]


# =========================================================== 0. 공통

@dataclass(frozen=True)
class PromptSpec:
    """하나의 AI 호출에 필요한 프롬프트 + 생성 파라미터 묶음.

    temperature를 여기 함께 두는 이유: 프롬프트와 온도는 세트로 튜닝된다.
    (관찰 추출은 저온, 서술은 고온) 따로 흩어지면 제어 지점이 두 곳으로 쪼개진다.
    """

    user_template: str
    system: str | None = None
    temperature: float = 0.7
    max_output_tokens: int = 2048
    response_schema: dict | None = None
    # 형식이 흔들릴 때 켜는 few-shot 예시. [(user, model), ...]
    examples: list[tuple[str, str]] = field(default_factory=list)

    def render(self, **kwargs) -> str:
        """user_template에 변수를 채워 반환."""
        return self.user_template.format(**kwargs)

    def tweak(self, **overrides) -> "PromptSpec":
        """일부 값만 바꾼 사본. 예: FRAME_EXTRACT.tweak(temperature=0.0)"""
        return replace(self, **overrides)


# =========================================================== 1. VLM: 프레임 관찰

_PRIVACY_RULES = """\
[개인정보 보호]
- 사람의 얼굴 생김새, 인종, 성별 추정, 나이 추정을 기록하지 않는다.
  "보행자", "자전거 이용자" 수준까지만 쓴다.
- 차량 번호판, 문패, 전화번호, 특정 상호명은 읽지 않고 기록하지 않는다.
  "카페 간판", "편의점"처럼 일반명사로만 쓴다.
- 공공 랜드마크(다리, 공원 이름, 역 이름)는 위치 파악에 필요하므로 기록해도 된다.
"""

FRAME_SYSTEM = """\
너는 산책 영상에서 추출된 프레임 이미지를 관찰해 기록하는 "산책 관찰 기록원"이다.
너의 출력은 이후 다른 AI가 산책 일지를 쓰기 위한 원자료로 쓰인다.
문학적 표현이 아니라 정확하고 검증 가능한 관찰을 남기는 것이 너의 임무다.

[관찰 원칙]
1. 이미지에 실제로 보이는 것만 기록한다. 보이지 않는 것을 그럴듯하게 채워 넣지 않는다.
2. 확실하지 않으면 "불명"을 쓴다. "불명"은 실패가 아니라 정상적인 답변이다.
3. 직접 보이는 사실과 그로부터의 추론을 구분하고, 추론에는 confidence를 매긴다.
4. 개수는 정확히 세지 말고 구간으로 답한다: "없음", "1", "2~5", "6~15", "다수".
5. 화면 왼쪽/오른쪽 같은 방향 표현은 확실할 때만 쓴다.

""" + _PRIVACY_RULES + """
[화질 안내]
입력 이미지는 압축되어 화질이 낮을 수 있다.
뭉개져서 판별이 안 되는 대상은 억지로 추측하지 말고 "불명"으로 처리한다.

[출력 형식]
JSON만 출력한다. 설명, 인사말, 마크다운 코드펜스를 붙이지 않는다.

[형식 예시]
아래는 형식만 참고하기 위한 예시다. 이 내용을 실제 관찰에 반영하지 마라.
{"scene":"젖은 보도블록 산책로가 앞으로 뻗어 있고 양옆으로 은행나무가 늘어서 있다.","location_type":"공원","surface":"보도블록","time_of_day":"낮","time_evidence":"하늘이 밝지만 그림자가 거의 없음","weather":"비","weather_evidence":"노면이 젖어 있고 보행자가 우산을 씀","season_hint":"가을","people":"2~5","animals":[],"plants":["은행나무"],"objects":["가로등","우산"],"atmosphere":["차분함","비온뒤","한적함"],"notable":"비가 그친 직후로 보이는 젖은 노면","confidence":{"time_of_day":0.6,"weather":0.9,"location_type":0.7},"unreadable":false}
"""

# 항목을 늘리거나 줄이려면 이 스키마와 FRAME_SYSTEM을 함께 손본다.
FRAME_SCHEMA: dict = {
    "type": "OBJECT",
    "properties": {
        "scene": {"type": "STRING", "description": "보이는 장면을 1~2문장으로 사실 위주 서술"},
        "location_type": {
            "type": "STRING",
            "enum": ["공원", "하천변", "주택가", "상가거리", "산길", "해변",
                     "학교주변", "차도변", "실내", "기타", "불명"],
        },
        "surface": {
            "type": "STRING",
            "enum": ["아스팔트", "보도블록", "흙길", "자갈", "데크", "잔디", "모래", "불명"],
        },
        "time_of_day": {
            "type": "STRING",
            "enum": ["새벽", "아침", "낮", "해질무렵", "밤", "불명"],
        },
        "time_evidence": {"type": "STRING", "description": "판단 근거. 없으면 빈 문자열"},
        "weather": {
            "type": "STRING",
            "enum": ["맑음", "구름많음", "흐림", "비", "눈", "안개", "불명"],
        },
        "weather_evidence": {"type": "STRING", "description": "판단 근거. 없으면 빈 문자열"},
        "season_hint": {"type": "STRING", "enum": ["봄", "여름", "가을", "겨울", "불명"]},
        "people": {"type": "STRING", "enum": ["없음", "1", "2~5", "6~15", "다수", "불명"]},
        "animals": {"type": "ARRAY", "items": {"type": "STRING"}},
        "plants": {"type": "ARRAY", "items": {"type": "STRING"}},
        "objects": {"type": "ARRAY", "items": {"type": "STRING"},
                    "description": "장면을 특징짓는 사물 최대 5개"},
        "atmosphere": {"type": "ARRAY", "items": {"type": "STRING"},
                       "description": "분위기 키워드 3개"},
        "notable": {"type": "STRING", "description": "특이사항 한 가지. 없으면 빈 문자열"},
        "confidence": {
            "type": "OBJECT",
            "properties": {
                "time_of_day": {"type": "NUMBER"},
                "weather": {"type": "NUMBER"},
                "location_type": {"type": "NUMBER"},
            },
        },
        "unreadable": {"type": "BOOLEAN",
                       "description": "너무 흐리거나 어두워 판별 불가할 때만 true"},
    },
    "required": ["scene", "location_type", "time_of_day", "weather",
                 "people", "atmosphere", "confidence", "unreadable"],
}

# Stage 1에는 examples를 쓰지 않는다.
# 이미지가 없는 텍스트 예시 턴을 앞에 붙이면 VLM이
# "이미지를 보지 않고도 JSON을 쓸 수 있다"고 학습해 환각이 늘어난다.
# 형식 학습은 FRAME_SYSTEM의 [형식 예시] 블록으로 대체했다.
# examples 필드는 이미지가 없는 Stage 2/3 전용으로 남겨둔다.

# [system / user 분리 기준]
#   system : 모든 프레임에 공통인 불변 규칙. 프레임 수만큼 곱해지지 않는다.
#   user   : 프레임마다 바뀌는 값 + 이미지. Gemini는 contents가 필수 필드이고
#            이미지도 이 user 턴의 parts에 담기므로, 자동 파이프라인이어도
#            user 파트는 생략할 수 없다.
#   마지막 두 줄의 지시는 system과 일부 겹치지만 의도한 중복이다.
#   이미지 바로 뒤(=입력의 끝)에 놓인 지시가 형식 준수율이 가장 높다.
FRAME_EXTRACT = PromptSpec(
    system=FRAME_SYSTEM,
    user_template="""\
[프레임 정보]
- 세그먼트: {segment}
- 산책 시작 후 경과: {elapsed}
- 촬영 일시: {shot_datetime}
- 위치: {location}

위 이미지를 관찰 원칙에 따라 기록하고 JSON만 출력해라.
촬영 일시가 주어졌다면 time_of_day는 그 값을 우선하고 confidence를 1.0으로 한다.\
""",
    temperature=0.1,          # 환각 억제. 올리면 없는 사물이 등장한다.
    max_output_tokens=2048,   # thinking 모델이 사고 토큰을 먼저 쓰므로 넉넉히.
    response_schema=FRAME_SCHEMA,
)


# =========================================================== 2. LLM: 일지 작성

_DIARY_SYSTEM_TEMPLATE = """\
너는 사용자의 산책을 대신 기록해 주는 일지 작가다.
입력으로 산책 중 촬영된 프레임들의 관찰 기록(JSON 배열)이 시간순으로 주어진다.
이것을 한 편의 산책 일지로 엮어라.

[작성 원칙]
1. 관찰 기록에 없는 사건, 감정, 대화를 지어내지 않는다.
   분위기 묘사는 기록에 실제로 있는 요소에서만 끌어온다.
2. 연속된 프레임은 대부분 같은 장면이다. 반복 서술하지 말고
   장면이 바뀌는 지점을 기준으로 문단을 나눈다.
3. confidence가 0.5 미만인 항목은 단정하지 말고 완화하거나 생략한다.
4. unreadable이 true인 프레임은 무시한다.
5. 기록이 서로 모순되면 더 많은 프레임의 값을 따르고,
   필요하면 "중간에 날이 흐려졌다"처럼 변화로 해석한다.
6. 사람에 대한 외모 묘사, 특정 상호명, 차량 번호는 절대 쓰지 않는다.

[문체]
<<STYLE>>

[출력 형식]
## {날짜} 산책 일지

**한 줄 요약**: (20자 이내)

(본문)

---
- 코스: (지나온 장소 유형을 순서대로)
- 날씨: (시간대 / 날씨)
- 오늘 만난 것: (인상적인 것 3개, 쉼표 구분)
"""

# 문체를 추가하려면 여기에 항목만 넣으면 된다.
DIARY_STYLES: dict[str, str] = {
    "plain": """\
- 1인칭 과거형. 담담하고 따뜻한 톤. 과장된 수사와 이모지는 쓰지 않는다.
- 분량: 본문 300~500자, 2~3문단.""",

    "emotional": """\
- 1인칭 과거형, 혼잣말하듯 짧은 문장.
- 풍경에서 느낀 감각(빛, 소리, 공기)을 한 문장 이상 담는다. 단, 기록에 있는 요소에서만.
- 분량: 본문 200~350자.""",

    "workout": """\
- 개조식 3~5줄. 코스, 노면, 환경 조건 위주로 쓰고 감상 표현은 최소화한다.
- 이모지와 수사를 쓰지 않는다.""",

    "pet": """\
- 반려견을 주인공으로 서술한다. 1인칭 과거형.
- animals에 반려견이 없는 프레임에서는 억지로 등장시키지 말고 환경만 기록한다.
- 분량: 본문 250~400자.""",
}

DEFAULT_DIARY_STYLE = "plain"

_DIARY_USER_TEMPLATE = """\
[산책 개요]
- 날짜: {walk_date}
- 총 소요: {duration}
- 프레임 수: {n_frames}

[관찰 기록 (시간순)]
{json_lines}

위 기록으로 산책 일지를 작성해라.\
"""


def diary_spec(style: str = DEFAULT_DIARY_STYLE) -> PromptSpec:
    """문체 프리셋을 적용한 일지 작성 스펙을 반환."""
    if style not in DIARY_STYLES:
        raise KeyError(f"등록되지 않은 문체: {style} (사용 가능: {list(DIARY_STYLES)})")
    return PromptSpec(
        system=_DIARY_SYSTEM_TEMPLATE.replace("<<STYLE>>", DIARY_STYLES[style]),
        user_template=_DIARY_USER_TEMPLATE,
        temperature=0.8,   # 문장 자연스러움. 밋밋하면 0.9~1.0까지 올려도 된다.
        max_output_tokens=2048,
    )


# =========================================================== 3. 이미지 생성 프롬프트 작성기

# 관찰 기록(한국어) -> 이미지 모델용 프롬프트(영어)로 번역/재구성하는 단계.
# 대부분의 이미지 생성 모델은 영어 프롬프트에서 성능이 좋고,
# 한국어 서술문보다 쉼표로 나열된 키워드 구조에 더 잘 반응한다.

IMAGE_PROMPT_WRITER = PromptSpec(
    system="""\
You are a prompt engineer for text-to-image models.
You receive Korean observation records from a walk, and write ONE image prompt in English.

Rules:
1. Use only elements present in the records. Do not invent landmarks or objects.
2. Output a comma-separated keyword sequence, not a sentence.
   Order: subject/scene, environment, time of day, weather, season, mood, composition.
3. Do NOT include any recognizable person, face, logo, brand name, text, or license plate.
   If people appear in the records, render them only as distant silhouettes.
4. Keep it under 60 words. Do not add style or quality keywords - those are appended separately.
5. Output the prompt only. No explanation, no quotes, no markdown.
""",
    user_template="""\
[Walk observation records]
{json_lines}

[Requested focus]
{focus}

Write one English image prompt describing the most representative scene of this walk.\
""",
    temperature=0.6,
    max_output_tokens=512,
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
5. Do NOT include any recognizable person, face, logo, brand name, text, or license plate.
   If people appear in the records, render them only as distant silhouettes.
6. Keep it under 60 words. Do not add style or quality keywords - those are appended separately.
7. Output the prompt only. No explanation, no quotes, no markdown.
""",
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
    max_output_tokens=512,
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
    max_output_tokens=64,
)


# =========================================================== 4. 이미지 생성 스타일

# 스타일을 추가하려면 여기에 항목만 넣으면 된다.
IMAGE_STYLES: dict[str, str] = {
    "watercolor": "soft watercolor illustration, gentle washes, visible paper texture, "
                  "muted palette, hand-painted feel",
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
    "oversaturated, cluttered, lowres, jpeg artifacts"
)

# 최종 조립 순서: 장면 프롬프트 -> 스타일 -> 공통 접미어
IMAGE_SUFFIX = "no text, no watermark"


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


# =========================================================== 5. 레지스트리

# 이름으로 스펙을 꺼내 쓰고 싶을 때. 함수형 스펙(diary)은 팩토리를 등록한다.
REGISTRY: dict[str, PromptSpec] = {
    "frame_extract": FRAME_EXTRACT,
    "diary": diary_spec(),
    "image_prompt_writer": IMAGE_PROMPT_WRITER,
    "flow_image_writer": FLOW_IMAGE_WRITER,
    "panel_caption_writer": PANEL_CAPTION_WRITER,
}


def get(name: str) -> PromptSpec:
    if name not in REGISTRY:
        raise KeyError(f"등록되지 않은 프롬프트: {name} (사용 가능: {list(REGISTRY)})")
    return REGISTRY[name]