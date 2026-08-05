"""프롬프트 스펙 컨테이너.

이 파일은 "그릇"만 정의한다. 실제 프롬프트 내용은 frame.py / diary.py / image.py에 있다.
외부 모듈을 import하지 않는다(표준 라이브러리 제외). prompts 패키지 전체가
API 키 없이 단독으로 import/테스트 가능해야 하기 때문이다.
"""

from __future__ import annotations

from dataclasses import dataclass, field, replace

__all__ = ["PromptSpec"]


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
    # 사고 토큰 예산. None이면 모델 기본값(요청에 필드를 넣지 않는다).
    # 0으로 내리면 사고를 끈다. Stage 1(관찰 기록)은 저온 + 스키마 강제이므로
    # 사고가 필요 없는데, 사고 토큰이 max_output_tokens를 먼저 소진하면
    # JSON이 잘려 프레임이 통째로 버려진다.
    # 프록시가 thinkingConfig를 지원하는지 먼저 확인해야 하므로 기본값은 None이다.
    thinking_budget: int | None = None

    def render(self, **kwargs) -> str:
        """user_template에 변수를 채워 반환."""
        return self.user_template.format(**kwargs)

    def tweak(self, **overrides) -> "PromptSpec":
        """일부 값만 바꾼 사본. 예: FRAME_EXTRACT.tweak(temperature=0.0)"""
        return replace(self, **overrides)