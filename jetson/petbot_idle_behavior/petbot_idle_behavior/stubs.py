"""
아직 실제 구현되지 않은 외부 연동 지점들의 스텁.
실제 연동이 준비되면 이 파일 하나만 고치면 되도록 idle_wander.py는
이 모듈의 함수만 호출하고 내부 구현을 알지 못하게 한다.
"""


def get_battery_level() -> float:
    """TODO: RPi5 UART 프로토콜(-196) 연동 완료되면 실제 값으로 교체.
    범위: 0.0 ~ 100.0 (%)
    """
    return 100.0  # 스텁: 항상 완충 상태


def get_affection_level() -> int:
    """TODO: 백엔드 애정도 API 연동 (엔드포인트 아직 미확정).
    범위: 0 ~ 100
    """
    return 50  # 스텁: 고정된 중간값


def get_check_owner_probability() -> float:
    """애정도 0~100 -> CHECK_OWNER로 갈 확률 0.05~0.4
    (애정도가 높을수록 주인을 더 자주 확인하러 감)
    """
    affection = get_affection_level()
    return 0.05 + (affection / 100.0) * 0.35

