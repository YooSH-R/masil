"""
관찰 기록에 쓰이는 어휘(enum) 단일 정의.

[왜 이 Vocab이 필요한가?]
    분할 전에는 enum의 값이 두 곳에 있었디.
    1) FRAME_SCHEMA의 "enum" 리스트 (모델이 강제로 지키는 값)
    2) FRAME_SYSTEM의 [형식예시] JSON (모델이 형식을 배우는 값)

값을 하나 추가할 때 한쪽만 고치면 스키마와 프롬프트가 어긋난다.
이제 스키마 조각은 전부 이 파일에서 생성한다.


[값을 추가할 때]
    아래 리스트만 고친다.
    FRAME_SCHEMA는 자동으로 따라온다.
    단 [형식 예시] JSON은 "예시"이므로 손으로 유지한다.
    - 예시에 없는 값을 추가하는 것은 정상이며, 예시를 매번 갱신할 필요는 없다.

리스트 순서는 모델에게 제시되는 순서다.
자주 등장하는 값을 앞에 두면 약하게나마 사전 확률로 작동하므로
순서를 무작위로 바꾸지 않는다.

"불명"은 항상 마지막에 둔다
"""

from __future__ import annotations

__all__ = [
    "UNKNOWN",
    "LOCATION_TYPES",
    "SURFACES",
    "TIMES_OF_DAY",
    "WEATHERS",
    "SEASON_HINTS",
    "PEOPLE_COUNTS",
    "enum_field",
    "text_field",
    "array_field",
    "options",
]


# 모든 enum이 공유하는 "판별 불가" 값.    관찰 원칙 2번의 핵심
UNKNOWN = "불명"

# ============================================
# TODO(분할 후 별도 커밋): "산책로" 추가 예정.
# 지금은 무손실 분할이라 값을 건드리지 않는다.
LOCATION_TYPES = [
    "공원", "하천변", "주택가", "상가거리", "산길", "해변",
    "학교주변", "차도변", "실내", "기타",
    UNKNOWN,
]

SURFACES = [
    "아스팔트", "보도블럭", "흙길", "자갈", "데크", "잔디", "모래",
    UNKNOWN,
]

TIMES_OF_DAY = [
    "새벽", "아침", "낮", "점심", "해질무렵", "저녁", "밤",
    UNKNOWN,
]

WEATHERS = [
    "맑음", "구름많음", "흐림", "비", "눈", "안개",
    UNKNOWN,
]

SEASON_HINTS = [
    "봄", "여름", "가을", "겨울",
    UNKNOWN,
]

#관찰 원칙 4번: 정확한 개수 대신 구간으로 답하게 한다.
PEOPLE_COUNTS = [
    "없음", "1", "2~5", "6~15", "다수",
    UNKNOWN,
]
# ============================================

# 스키마 조각
def enum_field(values: list[str], description: str | None = None) -> dict:
    """
    enumdl 걸린 string 필드.
    """

    field: dict = {"type": "STRING", "enum": list(values)}

    if description:
        field["description"] = description

    return field


def text_field(description: str | None = None) -> dict:
    """
    자유 서술 string 필드.
    """

    field: dict = {"type": "STRING"}

    if description:
        field["description"] = description

    return field


def array_field(description: str | None = None) -> dict:
    """
    문자열 배열 필드.
    """

    field: dict = {"type": "ARRAY", "items": {"type": "STRING"}}

    if description:
        field["description"] = description

    return field


def options(values: list[str]) -> str:
    """
    프롬프트 본문에 값을 나열할 때 쓴다.
    예: "공원|하천변|...."
    """

    return "|".join(values)