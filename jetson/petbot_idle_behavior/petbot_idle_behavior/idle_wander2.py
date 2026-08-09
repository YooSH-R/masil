#!/usr/bin/env python3
"""
웨이크워드 -> 제자리 회전하며 카메라(YOLO)로 사람 탐색 -> 사람 방향 직진 -> 라이다 전방 50cm 도달 시 정지
"""

from enum import Enum, auto

import rclpy
from cv_bridge import CvBridge
from geometry_msgs.msg import Twist
from rclpy.callback_groups import MutuallyExclusiveCallbackGroup
from rclpy.executors import MultiThreadedExecutor
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy
from sensor_msgs.msg import Image, LaserScan
from std_msgs.msg import Bool
from ultralytics import YOLO


ROTATE_ANGULAR_SPEED = 0.5        # rad/s (탐색 스윕 속도)
ROTATE_TIMEOUT_SEC = 15.0         # 15초 동안 못 찾으면 WAITING으로 복귀

APPROACH_LINEAR_SPEED = 0.15      # 직진 접근 속도 (m/s)
TARGET_STOP_DISTANCE_M = 0.50     # 🎯 전방 사람과의 목표 정지 거리 (50cm)
APPROACH_SAFETY_TIMEOUT_SEC = 12.0 # 안전용 최대 직진 시간 제한

MIN_CONFIDENCE = 0.5              # YOLO 사람 검출 최소 신뢰도

CENTER_TOLERANCE_NORM = 0.08      # 중앙 정렬 오차 범위
CENTERING_ANGULAR_SPEED = 0.15    # 중앙 정렬 저속 회전 속도
PERSON_TRACK_FRESHNESS_SEC = 1.0  # 추적 유효 시간
CENTERING_SIGN = -1               # 회전 방향 부호

TICK_PERIOD_SEC = 0.1             # 제어 루프 주기


class WanderState(Enum):
    WAITING = auto()
    SEARCHING = auto()
    APPROACHING = auto()


class IdleWander2Node(Node):

    def __init__(self):
        super().__init__('idle_wander2')

        self.state = WanderState.WAITING
        self.state_start_time = self.get_clock().now()

        self.last_offset = None
        self.last_offset_time = None
        self.front_distance = float('inf')  # 🎯 정면 라이다 실측 거리

        self.bridge = CvBridge()
        self.get_logger().info('YOLO 모델 로딩 중...')
        self.model = YOLO('yolov8n.pt')
        self.get_logger().info('YOLO 모델 로딩 완료')

        self.wakeword_sub = self.create_subscription(
            Bool, '/wakeword_detected', self._wakeword_callback, 10)

        scan_qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=10
        )

        self.scan_sub = self.create_subscription(
            LaserScan, '/scan', self._scan_callback, scan_qos)

        image_cb_group = MutuallyExclusiveCallbackGroup()
        image_qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=1)
        self.image_sub = self.create_subscription(
            Image, '/image_raw', self._image_callback, image_qos,
            callback_group=image_cb_group)

        self.cmd_vel_pub = self.create_publisher(Twist, '/cmd_vel', 10)
        self.approach_completed_pub = self.create_publisher(
            Bool, '/owner_approach_completed', 10)

        self.timer = self.create_timer(TICK_PERIOD_SEC, self._tick)
        self.get_logger().info('idle_wander2 준비 완료 - 웨이크워드 대기 중')

    def _scan_callback(self, msg: LaserScan):
        num_ranges = len(msg.ranges)
        if num_ranges == 0:
            return

        # 정면 ±15도 범위의 유효 라이다 거리 탐색
        window = max(1, int(num_ranges * (15.0 / 360.0)))
        front_ranges = msg.ranges[:window] + msg.ranges[-window:]
        valid_ranges = [r for r in front_ranges if msg.range_min <= r <= msg.range_max]

        if valid_ranges:
            self.front_distance = min(valid_ranges)
        else:
            self.front_distance = float('inf')

    def _wakeword_callback(self, msg: Bool):
        if not msg.data:
            return
        if self.state != WanderState.WAITING:
            self.get_logger().info('이미 탐색/접근 중이라 웨이크워드 무시')
            return
        self.get_logger().info('웨이크워드 감지 - 제자리 회전하며 사람 탐색 시작')
        self.last_offset = None
        self.last_offset_time = None
        self._transition_to(WanderState.SEARCHING)

    def _image_callback(self, msg: Image):
        frame = self.bridge.imgmsg_to_cv2(msg, desired_encoding='bgr8')
        width = frame.shape[1]
        # results = self.model.predict(frame, device=0, verbose=False, classes=[0])
        results = self.model.predict(frame, device='cpu', verbose=False, classes=[0])
        boxes = results[0].boxes

        best_idx, best_conf = None, 0.0
        for i in range(len(boxes)):
            conf = float(boxes.conf[i])
            if conf >= MIN_CONFIDENCE and conf > best_conf:
                best_idx, best_conf = i, conf
        if best_idx is None:
            return

        x1, y1, x2, y2 = boxes.xyxy[best_idx].tolist()
        offset = ((x1 + x2) / 2.0 - width / 2.0) / (width / 2.0)

        if self.state != WanderState.SEARCHING:
            return
        self.last_offset = offset
        self.last_offset_time = self.get_clock().now()

    def _transition_to(self, new_state):
        self.state = new_state
        self.state_start_time = self.get_clock().now()

    def _elapsed(self):
        return (self.get_clock().now() - self.state_start_time).nanoseconds / 1e9

    def _tick(self):
        if self.state == WanderState.SEARCHING:
            self._tick_searching()
        elif self.state == WanderState.APPROACHING:
            self._tick_approaching()

    def _tick_searching(self):
        if self._elapsed() >= ROTATE_TIMEOUT_SEC:
            self.get_logger().info('사람을 찾지 못함 - 탐색 중단')
            self._stop_and_wait()
            return

        offset = self._get_fresh_offset()
        twist = Twist()
        if offset is None:
            twist.angular.z = ROTATE_ANGULAR_SPEED
            self.cmd_vel_pub.publish(twist)
            return

        if abs(offset) <= CENTER_TOLERANCE_NORM:
            self.get_logger().info(f'사람 정면 정렬 완료 (offset={offset:+.2f}) - 직진 접근 시작')
            self._transition_to(WanderState.APPROACHING)
            return

        direction = 1 if offset > 0 else -1
        twist.angular.z = CENTERING_SIGN * direction * CENTERING_ANGULAR_SPEED
        self.cmd_vel_pub.publish(twist)

    def _get_fresh_offset(self):
        if self.last_offset is None or self.last_offset_time is None:
            return None
        age = (self.get_clock().now() - self.last_offset_time).nanoseconds / 1e9
        if age > PERSON_TRACK_FRESHNESS_SEC:
            return None
        return self.last_offset

    def _tick_approaching(self):
        # 🎯 라이다 정면 거리가 50cm(0.5m) 이하가 되거나 안전 타임아웃 경과 시 정지
        if self.front_distance <= TARGET_STOP_DISTANCE_M or self._elapsed() >= APPROACH_SAFETY_TIMEOUT_SEC:
            self.get_logger().info(
                f'🎉 사람 전방 50cm 접근 완료! (실측 거리: {self.front_distance:.2f}m) - 안전 정지'
            )
            self.approach_completed_pub.publish(Bool(data=True))
            self._stop_and_wait()
            return

        twist = Twist()
        twist.linear.x = APPROACH_LINEAR_SPEED
        self.cmd_vel_pub.publish(twist)

    def _stop_and_wait(self):
        self.cmd_vel_pub.publish(Twist())
        self._transition_to(WanderState.WAITING)


def main(args=None):
    rclpy.init(args=args)
    node = IdleWander2Node()
    executor = MultiThreadedExecutor(num_threads=2)
    executor.add_node(node)
    try:
        executor.spin()
    except KeyboardInterrupt:
        pass
    finally:
        executor.shutdown()
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()
