"""
Idle 배회 로직 (S15P11A203-208)

혼자 있을 때 REST(휴식)/PATROL(짧은 순찰)/CHECK_OWNER(가끔 주인 확인)/
DOCKING(배터리 위급 시 충전)을 오가는 상태 머신.

사람 위치는 person_locator.py가 이미 발행 중인 /person_location을
구독해서 얻는다 (YOLO를 또 로드하지 않음 - Jetson 리소스 절약, -140/-127
등 앞으로 사람 위치가 필요한 기능들도 person_locator 하나만 공용으로
쓰게 하려는 의도).
"""

import math
import random
from enum import Enum, auto

import rclpy
from geometry_msgs.msg import PointStamped
from rclpy.node import Node

from petbot_idle_behavior.stubs import get_battery_level, get_check_owner_probability
from petbot_idle_behavior.waypoints import PATROL_WAYPOINTS
from petbot_nav_interface.move_interface import MoveInterface


REST_MIN = 180.0                    # sec
REST_MAX = 480.0                    # sec
CHECK_OWNER_DURATION = 5.0          # sec
BATTERY_CRITICAL_THRESHOLD = 15.0   # %
TICK_PERIOD_SEC = 1.0

# person_locator.py는 사람이 감지될 때만 /person_location을 발행한다
# (주기적 heartbeat 없음). 이보다 오래된 메시지는 "지금은 안 보임"으로 취급.
PERSON_POSITION_FRESHNESS_SEC = 3.0

# person_approach.py(APPROACH_STOP_DISTANCE)와 동일한 철학: 사람 좌표
# 정확히 그 지점이 아니라 이 거리만큼 앞에서 멈추게 한다 (충돌 방지).
CHECK_OWNER_STOP_DISTANCE = 0.6     # m


class WanderState(Enum):
    REST = auto()
    PATROL = auto()
    CHECK_OWNER = auto()
    DOCKING = auto()


class IdleWanderNode(Node):
    def __init__(self):
        super().__init__('idle_wander')

        self.state = WanderState.REST
        self.state_enter_time = self.get_clock().now()
        self.just_entered = True
        self.rest_duration = 0.0

        self.latest_person_point = None
        self.latest_person_received_at = None

        self.person_sub = self.create_subscription(
            PointStamped, '/person_location', self._person_location_callback, 10)

        self.mover = MoveInterface('idle_wander_mover')
        self.get_logger().info('Nav2 준비 대기 중...')
        self.mover.wait_until_ready()
        self.get_logger().info('Nav2 준비 완료 - idle wander 시작')

        self.timer = self.create_timer(TICK_PERIOD_SEC, self._tick)

        self.get_logger().info('초기 상태: REST')

    def _person_location_callback(self, msg):
        self.latest_person_point = msg
        self.latest_person_received_at = self.get_clock().now()

    def _get_fresh_person_point(self):
        if self.latest_person_point is None or self.latest_person_received_at is None:
            return None
        age_sec = (self.get_clock().now() - self.latest_person_received_at).nanoseconds / 1e9
        if age_sec > PERSON_POSITION_FRESHNESS_SEC:
            return None
        return self.latest_person_point

    def _elapsed_in_state(self):
        return (self.get_clock().now() - self.state_enter_time).nanoseconds / 1e9

    def _transition_to(self, new_state):
        self.get_logger().info(f'상태 전환: {self.state.name} -> {new_state.name}')
        self.state = new_state
        self.state_enter_time = self.get_clock().now()
        self.just_entered = True

    def _tick(self):
        self._check_battery_priority()

        if self.state == WanderState.REST:
            self._tick_rest()
        elif self.state == WanderState.PATROL:
            self._tick_patrol()
        elif self.state == WanderState.CHECK_OWNER:
            self._tick_check_owner()
        elif self.state == WanderState.DOCKING:
            self._tick_docking()

    def _check_battery_priority(self):
        if self.state == WanderState.DOCKING:
            return
        battery = get_battery_level()
        if battery <= BATTERY_CRITICAL_THRESHOLD:
            self.get_logger().warn(
                f'배터리 위급 ({battery:.1f}% <= {BATTERY_CRITICAL_THRESHOLD}%) '
                f'- {self.state.name}에서 DOCKING으로 강제 전환')
            if self.state == WanderState.PATROL:
                self.mover.cancel()
            self._transition_to(WanderState.DOCKING)

    def _tick_rest(self):
        if self.just_entered:
            self.rest_duration = random.uniform(REST_MIN, REST_MAX)
            self.get_logger().info(
                f'REST 진입 - {self.rest_duration:.1f}초 후 PATROL로 전환 예정')
            self.just_entered = False
            return
        if self._elapsed_in_state() >= self.rest_duration:
            self._transition_to(WanderState.PATROL)

    def _tick_patrol(self):
        if self.just_entered:
            wx, wy = random.choice(PATROL_WAYPOINTS)
            self.get_logger().info(f'PATROL 진입 - 웨이포인트 ({wx}, {wy})로 이동 시작')
            self.mover.move_to(wx, wy, frame_id='map')
            self.just_entered = False
            return

        if self.mover.is_done():
            result = self.mover.get_result()
            self.get_logger().info(f'PATROL: 웨이포인트 도착 (결과={result})')
            probability = get_check_owner_probability()
            if random.random() < probability:
                self._transition_to(WanderState.CHECK_OWNER)
            else:
                self._transition_to(WanderState.REST)

    def _tick_check_owner(self):
        if self.just_entered:
            target = self._get_fresh_person_point()
            if target is None:
                self.get_logger().info(
                    'CHECK_OWNER: 최근 사람 위치 없음 - 즉시 REST로 복귀')
                self._transition_to(WanderState.REST)
                return

            # /person_location은 frame_id='laser_frame'이지만, URDF상
            # laser_frame과 base_link는 x,y 원점이 같아서(lidar_x=lidar_y=0.0)
            # 좌표 변환 없이 그대로 base_link 기준으로 써도 된다.
            px, py = target.point.x, target.point.y
            distance = math.hypot(px, py)
            if distance <= CHECK_OWNER_STOP_DISTANCE:
                # 이미 충분히 가까움 - 이동 없이 그냥 대기만
                self.get_logger().info(
                    f'CHECK_OWNER 진입 - 이미 가까움 (거리={distance:.2f}m), 이동 생략')
            else:
                ux, uy = px / distance, py / distance
                target_distance = distance - CHECK_OWNER_STOP_DISTANCE
                goal_x, goal_y = ux * target_distance, uy * target_distance
                self.get_logger().info(
                    f'CHECK_OWNER 진입 - 사람 방향으로 이동 '
                    f'(x={goal_x:.2f}, y={goal_y:.2f}, frame=base_link)')
                self.mover.move_to(goal_x, goal_y, frame_id='base_link')
            self.just_entered = False
            return

        # 타이머 기반 종료: 이동 완료 여부와 무관하게 CHECK_OWNER_DURATION 경과 시 REST로.
        if self._elapsed_in_state() >= CHECK_OWNER_DURATION:
            self.get_logger().info('CHECK_OWNER: 대기 시간 경과 - REST로 복귀')
            self._transition_to(WanderState.REST)

    def _tick_docking(self):
        if self.just_entered:
            self.get_logger().warn(
                'DOCKING 진입 (스텁) - 실제 도킹 스테이션 탐지/이동은 미구현 '
                '(별도 티켓 예정). 지금은 "도킹 완료"로 간주하고 REST로 복귀합니다.')
            self.just_entered = False
            return
        self._transition_to(WanderState.REST)


def main(args=None):
    rclpy.init(args=args)
    node = IdleWanderNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()
