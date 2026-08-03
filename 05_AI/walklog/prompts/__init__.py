"""프롬프트 중앙 관리 패키지.

AI의 동작을 바꾸고 싶으면 이 패키지만 수정하면 된다.
실행 로직(API 호출, 이미지 압축, 파일 I/O)은 여기에 두지 않는다.

[구성]
  spec.py   PromptSpec 정의 (그릇)
  vocab.py  enum 어휘 단일 정의 + 스키마 조각 생성
  rules.py  스테이지 공통 정책(개인정보) + 블록 합성 헬퍼
  frame.py  Stage 1 - VLM 프레임 관찰 기록
  diary.py  Stage 2 - 산책 일지 작성 (+ 문체 프리셋)
  image.py  Stage 3 - 이미지 프롬프트 작성기 (+ 스타일 프리셋)

[불변 규칙]
1. 이 패키지는 외부 의존이 없다. requests, cv2, config를 import하지 않는다.
   API 키 없이 import되고 테스트되어야 한다.
2. 변수 치환 방식은 두 가지뿐이며 섞지 않는다.
     system        : <<NAME>> 센티널 + str.replace  (출력 예시용 중괄호가 있으므로)
     user_template : str.format
3. 동기화가 필수인 문구(개인정보 정책)는 rules.py에, enum 값은 vocab.py에 둔다.
   그 외의 중복은 의도적으로 허용한다. 스테이지별로 따로 튜닝되기 때문이다.
"""

from __future__ import annotations

from typing import Callable

from . import rules, vocab
from .diary import DEFAULT_DIARY_STYLE, DIARY_STYLES, diary_spec
from .frame import FRAME_EXTRACT, FRAME_SCHEMA, FRAME_SYSTEM
from .image import (
    DEFAULT_IMAGE_STYLE,
    FLOW_IMAGE_WRITER,
    IMAGE_NEGATIVE,
    IMAGE_PROMPT_WRITER,
    IMAGE_STYLES,
    IMAGE_SUFFIX,
    PANEL_CAPTION_WRITER,
    STORY_IMAGE_WRITER,
    build_image_prompt,
    build_image_request,
)
from .spec import PromptSpec

# 프롬프트 세대 표시. 관찰 기록에 함께 저장해 두면, 프롬프트를 손보는 동안
# 쌓인 기록들이 서로 비교 불가능한 데이터가 되는 것을 막는다.
# 프롬프트 내용을 바꿀 때 이 값을 올린다.
PROMPT_VERSION = "2026-07-29"

__all__ = [
    "PROMPT_VERSION",
    "PromptSpec",
    "FRAME_EXTRACT",
    "FRAME_SCHEMA",
    "FRAME_SYSTEM",
    "DIARY_STYLES",
    "DEFAULT_DIARY_STYLE",
    "diary_spec",
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
    "REGISTRY",
    "get",
    "rules",
    "vocab",
]


# 이름으로 스펙을 꺼내 쓰고 싶을 때.
# 인자를 받는 스펙(diary)은 팩토리로 등록해 호출 시점에 만든다.
_FACTORIES: dict[str, Callable[..., PromptSpec]] = {
    "frame_extract": lambda: FRAME_EXTRACT,
    "diary": diary_spec,
    "image_prompt_writer": lambda: IMAGE_PROMPT_WRITER,
    "flow_image_writer": lambda: FLOW_IMAGE_WRITER,
    "story_image_writer": lambda: STORY_IMAGE_WRITER,
    "panel_caption_writer": lambda: PANEL_CAPTION_WRITER,
}


def get(name: str, **kwargs) -> PromptSpec:
    """이름으로 스펙을 얻는다. diary처럼 인자를 받는 스펙은 kwargs를 넘긴다.

    예: get("diary", style="emotional")
    """
    if name not in _FACTORIES:
        raise KeyError(f"등록되지 않은 프롬프트: {name} (사용 가능: {list(_FACTORIES)})")
    return _FACTORIES[name](**kwargs)


# 기존 호출부 호환용. 분할 전 prompts.REGISTRY와 동일한 dict를 제공한다.
# 새 코드는 get()을 쓴다. 참조가 없는 것을 확인하면 이 변수를 제거한다.
REGISTRY: dict[str, PromptSpec] = {name: factory() for name, factory in _FACTORIES.items()}