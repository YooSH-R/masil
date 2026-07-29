"""
Stage 2 - LLM: 관찰 기록 JSON 배열 -> 자연어 산책 일지.

이미지를 보지 않는다. Stage 1이 남긴 기록만이 사실의 원천이다.
따라서 이 단계의 핵심 제약은 "기록에 없는 것을 쓰지 않기"다.
"""

from __future__ import annotations
from . import rules
from .spec import PromptSpec

__all__ = ["DIARY_STYLES", "DEFAULT_DIARY_STYLE", "diary_spec"]


# 이 템플릿에는 출력 형식 예시용 중괄호({날짜})가 들어 있으므로 .format()을 쓰지 않는다.
# 변수는 <<NAME>> 센티널 + replace로만 채운다.

_DIARY_SYSTEM_TEMPLATE = """\
너는 사용자의 산책을 대신 기록해 주는 일지 작가다.
입력으로 산책 중 촬영된 프레임들의 관찰 기록(JSON 배열)이 시간순으로 주어진다.
이것을 한 편의 산책 일지로 엮어라.

[작성 원칙]
1. 관찰 기록에 없는 시간, 감정, 대화를 지어내지 않는다. 분위기 묘사는 기록에 실제로 있는 요소에서만 끌어온다.
2. 연속된 프레임은 대부분 같은 장면이다. 반복 서술하지 말고 장면이 바뀌는 지점을 기준으로 문단을 나눈다.
3. confidence가 0.5 미만인 항목은 단정하지 말고 완화하거나 생략한다.
4. unreadable이 true인 프레임은 무시한다.
5. 기록이 서로 모순되면 더 많은 프레임의 값을 따르고, 필요하면 "중간에 날이 흐려졌다"처럼 변화로 해석한다.
6. <<PRIVACY>>

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
# 각 프리셋은 [문체] 블록을 통째로 대체하므로, 다른 프리셋의 지시를 상속하지 않는다.
DIARY_STYLES: dict[str, str] = {
    "plain": """\
- 1인칭 과거형. 담담하고 따뜻한 톤. 과장된 수사와 이모지는 쓰지 않는다.
- 분량: 본문 300~500자, 2~3문단.
""",

    "emotional": """\
- 1인칭 과거형, 혼잣말하듯 짧은 문장.
- 풍경에서 느낀 감각(빛, 소리, 공기)을 한 문장 이상 담는다. 단, 기록에 있는 요소에서만.
- 분량: 본문 200~350자.
""",

    "workout": """\
- 개조식 3~5줄, 코스, 노면, 환경 조건 위주로 쓰고 감상 표현은 최소화 한다.
- 이모지와 수사를 쓰지 않는다.
""",

    "pet": """\
- 반려견을 주인공으로 서술한다. 1인칭 과거형.
- animals에 반려견이 없는 프레임에서는 억지로 등장시키지 말고 환경만 기록한다.
- 분량: 본문 250~400자.
""",
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
    """
    문체 프리셋을 적용한 일지 작성 스펙을 반환.
    """
    if style not in DIARY_STYLES:
        raise KeyError(f"등록되지 않은 문체: {style} (사용 가능: {list(DIARY_STYLES)})")
    system = (
        _DIARY_SYSTEM_TEMPLATE
        .replace("<<PRIVACY>>", rules.PRIVACY_KO_ONELINE)
        .replace("<<STYLE>>", DIARY_STYLES[style])
    )

    return PromptSpec(
        system=system,
        user_template=_DIARY_USER_TEMPLATE,
        temperature=0.8,            # 문장의 자연스러움, 밋밋하면 0.9~1.0까지 올려도 된다.
        max_output_tokens=2048,
    )