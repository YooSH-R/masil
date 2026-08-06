"""
여러 스테이지에 공통적으로 들어가는 정책 블록.

[무엇을 여기 두고 무엇을 두지 않는가]
    여기에 두는 것:
        스테이지가 달라져도 반드시 같아야 하는 "정책".
        개인정보 보호가 대표적이다.
    
        Stage1이 상호명을 기록하지 않는데, Stage3이 상호명을 기록하면 정책에 구멍이난다.
        따라서 문구가 흩어져 있으면 안된다.

    여기에 두지 않는 것:
        스테이지마다 의도적으로 다른 "작성 지침".
        예를 들어 "쉼표로 구분된 키워드로 출력" 같은 규칙은
        이미지 프롬프트 작성 시 두 곳에 중복되어 있지만,
        한쪽이 나중에 달라질 수 있는 성질의 것이므로 각 파일에 남겨둔다.

        중복 제거는 목적이 아니고, 동기화가 필요한 것만 모으는 것이 목적이다.
"""

from __future__ import annotations

__all__ = ["PRIVACY_KO", "PRIVACY_KO_ONELINE", "PRIVACY_EN", "join"]


# Stage 1(관찰 기록)용 전문.
# 기록 단계에서 애초에 남기지 않는 것이 가장 확실한 방어이다.
PRIVACY_KO = """\
[개인정보 보호]
- 사람의 얼굴, 생김새, 인종, 성별 추정, 나이 추정을 기록하지 않는다. "보행자", "자전거 이용자" 수준까지만 쓴다.
- 차량 번호판, 문패, 전화번호, 특정 상호명은 읽지 않고 기록하지 않는다. "카페 간판", "편의점"처럼 일반명사로만 쓴다.
- 공공 랜드마크(다리, 공원 이름, 역 이름)는 위치 파악에 필요하므로 기록해도 된다.
"""


# Stage 2(일지) 작성 원칙 목록에 한 줄로 삽입되는 축약판.
    # Stage 1이 이미 걸러주지만, 관찰 기록에 실수로 남았을 때의 2차 방어선이다.
PRIVACY_KO_ONELINE = "사람에 대한 외모 묘사, 특정 상호명, 차량 번호는 절대 쓰지 않는다."


# Stage 3(이미지 프롬프트) 영어판.
    # 번호 붙은 목록 안에 삽입되므로 둘째 줄 들여쓰기 3칸을 유지해야 한다.
    #
    # 인물을 "먼 실루엣으로만 그려라"는 완화 서술이었으나, 2026-08-05
    # session3 event_02에서 "silhouette of a person's head" 서술을 이미지
    # 모델이 식별 가능한 얼굴(눈/눈썹)로 승격시킨 사례가 확인됐다. 실루엣도
    # "사람이 있다"는 신호를 남기면 모델이 디테일을 채워 넣을 여지가
    # 생기므로, 완화가 아니라 전면 배제로 바꿨다. 관찰 기록(FRAME_EXTRACT)의
    # people 필드는 기록이 사실이어야 하므로 그대로 둔다 - 배제는 이미지
    # 프롬프트 단계에서만 적용한다.
PRIVACY_EN = """\
Do Not include any recognizable person, face, logo, brand name, text, or license plate.
   Do not include people, human figures, faces, or body parts in the prompt at all -
   omit them from the scene entirely, even if they appear in the records or reference.
   Describe the scene as if no person were present.
"""


def join(*blocks: str) -> str:
    """
    블록들을 빈 줄 하나로 이어 붙인다.
    
    시스템 프롬프트를 하나의 긴 문자열로 두지 않고 명명된 블록의 합성으로 만들면
    블록 순서 변경과 추가/제거가 한 줄 편집이 된다.
    각 블록의 앞뒤 공백은 벗기므로 블록 내부만 신경 쓰면 되고,
    블록 사이 개행 개수는 이 함수가 보장한다.
    """

    return "\n\n".join(b.strip() for b in blocks if b and b.strip())