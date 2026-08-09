"""
move_interface.py 동작 확인용 간단 테스트.
실행: ros2 run petbot_nav_interface move_test
"""

import rclpy
from petbot_nav_interface.move_interface import MoveInterface


def main():
    rclpy.init()
    mover = MoveInterface()

    print("Nav2 준비 대기 중...")
    mover.wait_until_ready()
    print("Nav2 준비 완료. 목표(1.0, 0.5)로 이동 시작")

    mover.move_to(1.0, 0.5)

    while not mover.is_done():
        feedback = mover.get_feedback()
        if feedback:
            print(f"남은 거리: {feedback.distance_remaining:.2f} m")
        rclpy.spin_once(mover.navigator, timeout_sec=0.5)

    print("이동 결과:", mover.get_result())
    rclpy.shutdown()


if __name__ == "__main__":
    main()
