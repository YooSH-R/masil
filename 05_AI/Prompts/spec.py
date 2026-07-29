"""
프롬프트 스펙 컨테이너

이 파일은 "그릇"만 정의한다.
실제 프롬프트 내용은 frame.py / diray.py / image.py 등 Prompts 디렉토리 내 역할 부분에 속해앴다
외부 모듈은 import 하지 않는다(표준 라이브러리 제외)
prompts 패키지 전체가 API 키 없이 단독으로 import/테스트가 가능해야 하기 때문이다.
"""

from __future__ import annotations
from dataclasses import dataclass, field, replace

__all__ = ["PromptSpec"]


@dataclass(frozen=True)
class PromptSpec:
    """
    하나의 AI 호출에 필요한 프롬프트 + 생성 파라미터 묶음.

    temperature를 여기에 함께 두는 이유
        - 프롬프트와 온도는 세트로 튜닝한다.
        (관찰 추출은 저온, 서술은 고온) 따로 흩어지면 제어 지점이 두 곳으로 쪼개진다.
    """

    user_template: str
    system: str | None = None
    temperature: float = 0.7
    max_output_tokens: int = 2048
    response_schema: dict | None = None
    # 형식이 흔들릴 때 켜는 few-shot 예시
    # [(user, mode1), ...]
    examples: list[tuple[str, str]] = field(default_factory=list)


    def render(self, **kwargs) -> str:
        """
        user_template에 변수를 채워 반환.
        """
        return self.user_template.format(**kwargs)

    def tweak(self, **overrides) -> "PromptSpec":
        """
        일부 값만 바꾼 사본.
        예: FRAME_EXTRACT.tweak(temperature=0.0)
        """
        return replace(self, **overrides)
