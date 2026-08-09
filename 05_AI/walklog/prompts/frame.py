"""
Stage 1 - VLM: 프레임 이미지 1장 -> 구조화 JSON 관찰 기록.

이 단계의 산출물은 사람이 읽는 글이 아니라 Stage 2/3의 입력 데이터다.
따라서 목표는 "좋은 문장"이 아니라 "검증 가능한 사실"이다.
"""

from __future__ import annotations
from . import rules, vocab
from .spec import PromptSpec

__all__ = ["FRAME_SYSTEM", "FRAME_SCHEMA", "FRAME_EXTRACT"]


# ========== 시스템 프롬프트 블록 ==========
_ROLE = """\
너는 산책 영상에서 추출된 프레임 이미지를 관찰해 기록하는 "산책 관찰 기록원"이다.
너의 출력은 이후 다른 AI가 산책 일지를 쓰기 위한 원자료로 쓰인다.
문학적 표현이 아니라 정확하고 검증 가능한 관찰을 남기는 것이 너의 임무다.
"""

_OBSERVATION_RULES="""\
[관찰 원칙]
1. 이미지에 실제로 보이는 것만 기록한다. 보이지 않는 것을 그럴듯하게 채워 넣지 않는다.
2. 확실하지 않으면 "불명"을 쓴다. "불명"은 실패가 아니라 정상적인 답변이다.
3. 직접 보이는 사실과 그로부터 추론을 구분하고, 추론에는 confidence를 매긴다.
4. 개수는 정확히 세지 말고 구간으로 답한다: "없음", "1", "2~5", "6~15", "다수".
5. 화면 왼쪽/오른쪽 같은 방향 표현은 확실할 때만 쓴다.
6. indoor: 실내(건물 안, 지하, 차량 내부)인지 판정한다. 확신이 없으면
   천장 조명, 창문 유무, 하늘 노출을 근거로 판단한다.
"""

_IMAGE_QUALITY = """\
[화질 안내]
입력 이미지는 압축되어 화질이 낮을 수 있다.
뭉개져서 판별이 안 되는 대상은 억지로 추측하지 말고 "불명"으로 처리한다.
"""

_OUTPUT_FORMAT = """\
[출력 형식]
JSON만 출력한다.
설명, 인사말, 마크다운 코드펜스를 붙이지 않는다.
"""


# 이 블록에는 중괄호{}가 들어가 있다.
## .format()을 쓰면 KeyError가 난다.
## 변수를 꽂아야 한다면 <<NAME>> 센티널 + replace를 쓴다.
_FORMAT_EXAMPLE = """\
[형식 예시]
아래는 형식만 참고하기 위한 예시다.
이 내용을 실제 관찰에 반영하지 마라.
{
"scene": "젖은 보도블록 산책로가 앞으로 뻗어 있고 양 옆으로 은행나무가 늘어서 있다.",
"location_type": "공원",
"surface": "보도블록",
"time_of_day": "낮",
"time_evidence": "하늘이 밝지만 그림자가 거의 없음",
"weather": "맑음",
"weather_evidence": "밝은 화면과 보행자들이 우산 없이 지나가고 있음",
"season_hint": "가을",
"people": "2~5",
"animals": [],
"plants": ["은행나무"],
"objects": ["가로등", "벤치"],
"atmosphere": ["차분함", "비온뒤", "한적함"],
"notable": "비가 그친 직후로 보이는 젖은 노면",
"confidence": {
    "time_of_day": 0.6,
    "weather": 0.9,
    "location_type": 0.7
    },
"unreadable": false,
"indoor": false
}
"""

# 블록 순서: 역할 -> 관찰 원칙 -> 개인정보 -> 화질 -> 출력 형식 -> 형식 예시
# 형식에 관한 지시를 끝에 두는 이유는 입력의 끝에 가까울수록 준수율이 높기 때문이다.
FRAME_SYSTEM = rules.join(
    _ROLE,
    _OBSERVATION_RULES,
    rules.PRIVACY_KO,
    _IMAGE_QUALITY,
    _OUTPUT_FORMAT,
    _FORMAT_EXAMPLE,
) + "\n"



# ========== 응답 스키마 ==========
# enum 값은 vocab.py에서 온다.
# 항목 자체를 늘리거나 줄이려면 이 스키마와 _FORMAT_EXAMPLE을 함께 손본다.
FRAME_SCHEMA: dict = {
    "type": "OBJECT",
    "properties": {
        "scene": vocab.text_field("보이는 장면을 1~2문장으로 사실 위주 서술"),
        "location_type": vocab.enum_field(vocab.LOCATION_TYPES),
        "surface": vocab.enum_field(vocab.SURFACES),
        "time_of_day": vocab.enum_field(vocab.TIMES_OF_DAY),
        "time_evidence": vocab.text_field("판단 근거. 없으면 빈 문자열"),
        "weather": vocab.enum_field(vocab.WEATHERS),
        "weather_evidence": vocab.text_field("판단 근거. 없으면 빈 문자열"),
        "season_hint": vocab.enum_field(vocab.SEASON_HINTS),
        "people": vocab.enum_field(vocab.PEOPLE_COUNTS),
        "animals": vocab.array_field(),
        "plants": vocab.array_field(),
        "objects": vocab.array_field("장면을 특징짓는 사물 최대 5개"),
        "atmosphere": vocab.array_field("분위기 키워드 3개"),
        "notable": vocab.text_field("특이사항 한가지. 없으면 빈 문자열"),
        "confidence": {
            "type": "OBJECT",
            "properties": {
                "time_of_day": {"type": "NUMBER"},
                "weather": {"type": "NUMBER"},
                "location_type": {"type": "NUMBER"},
            },
        },
        "unreadable": {
            "type": "BOOLEAN",
            "description": "너무 흐리거나 어두워 판별 불가할 때만 true",
        },
        "indoor": {
            "type": "BOOLEAN",
            "description": "실내(건물 안, 지하, 차량 내부)면 true. "
                           "하늘/지평선이 보이거나 야외 지면이면 false",
        },
    },

    "required": ["scene", "location_type", "time_of_day", "weather", "people",
                "atmosphere", "confidence", "unreadable", "indoor"],
}


# ========== 스펙 ==========

# Stage 1에는 examples를 쓰지 않는다.
# 이미지가 없는 텍스트 예시 턴을 앞에 붙이면 VLM이 "이미지를 보지 않고도 JSON을 쓸 수 있다"고 학습해 환각이 늘어난다.
# 형식 학습은 FRAME_SYSTEM의 [형식 예시] 블록으로 대체했다.
# examples 필드는 이미지가 없는 Stage 2/3 전용으로 남겨둔다.

# [system / user 분리 기준]
#   system: 모든 프레임에 공통인 불변 규칙.
#           프레임 수 만큼 곱해지지 않는다.
#   user:   프레임마다 바뀌는 값 + 이미지.
#           Gemini는 contents가 필수 필드이고 이미지도 이 user 턴의 parts에 담기므로,
#           자동화 파이프라인이어도 user 파트는 생략할 수 없다.
#
# 마지막 두 줄의 지시는 system과 일부 겹치지만 의도한 중복이다.
# 이미지 바로 뒤(=입력의 끝)에 놓인 지시가 형식 준수율이 가장 높다.
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

    temperature=0.1,                # 환각 억제, 온도를 올리면 없는 사물이 등장한다.
    max_output_tokens=4096,         # thinking 모델이 사고 토큰을 먼저 쓰므로 넉넉히.
    response_schema=FRAME_SCHEMA,
)
