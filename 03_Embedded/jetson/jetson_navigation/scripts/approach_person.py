#!/usr/bin/env python3
"""웨이크워드 -> 제자리 회전하며 YOLO로 사람 탐색 -> 정면 정렬 -> 라이다 전방 50cm 까지 접근.

원본: 다른 개발자 워크스페이스의 petbot_idle_behavior/idle_wander2.py
우리 로봇에 맞춰 아래를 수정했다.

  1) 정면 라이다 구간: 원본은 ranges 배열의 앞/뒤 끝을 정면으로 가정했으나,
     우리 라이다는 angle_min=-180, angle_max=+180 이라 배열 양 끝이 '뒤쪽'이다.
     게다가 라이다가 90도 돌아 장착돼 있어(base_link->laser_frame yaw = -1.5708)
     로봇 정면은 스캔 각도 +90도에 있다. 각도로 인덱스를 계산하도록 바꾸고,
     부호를 실기에서 뒤집을 수 있게 파라미터(front_angle_deg)로 뺐다.
  2) 탐색 회전 속도 0.5 -> 0.3: /scan 에 88ms 고정 지연이 있어 회전이 빠를수록
     스캔이 각도만큼 밀린다. Nav2/AMCL 이 같이 떠 있을 때 위치추정이 깨지는 것을 방지.
  3) 안전 타임아웃으로 멈춘 경우에는 /owner_approach_completed 를 쏘지 않는다
     (원본은 실패해도 성공으로 발행했다).
  4) YOLO 디바이스를 파라미터화(device: 'cpu' | '0'). 젯슨 GPU 여유가 있으면 '0'.

실행 (yolo-env venv 필요):
  source ~/yolo-env/bin/activate
  source /opt/ros/humble/setup.bash
  python3 ~/ros_ws/src/jetson_navigation/scripts/approach_person.py

정면 방향 검증(중요):
  로봇 정면 1m 앞에 상자를 두고 아래 로그의 front=... 값이 1.0 근처인지 확인.
  엉뚱하면 front_angle_deg 를 -90 으로 바꿔서 재실행.
    python3 approach_person.py --ros-args -p front_angle_deg:=-90.0
"""

import math
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

ROTATE_ANGULAR_SPEED = 0.3         # rad/s (원본 0.5 -> 스캔 왜곡 줄이려고 낮춤)
ROTATE_TIMEOUT_SEC = 20.0          # 못 찾으면 대기 상태로 복귀

APPROACH_LINEAR_SPEED = 0.15       # m/s
TARGET_STOP_DISTANCE_M = 0.50      # 전방 목표 정지 거리
APPROACH_SAFETY_TIMEOUT_SEC = 12.0 # 안전용 최대 직진 시간

MIN_CONFIDENCE = 0.5
CENTER_TOLERANCE_NORM = 0.08
CENTERING_ANGULAR_SPEED = 0.15
PERSON_TRACK_FRESHNESS_SEC = 1.0
CENTERING_SIGN = -1                # 중앙 정렬 회전 부호 (실기에서 반대면 +1)

TICK_PERIOD_SEC = 0.1


class WanderState(Enum):
    WAITING = auto()
    SEARCHING = auto()
    APPROACHING = auto()


class ApproachPersonNode(Node):

    def __init__(self):
        super().__init__('approach_person')

        # 로봇 정면이 laser_frame 기준 몇 도인지. 장착 yaw -90도 -> 정면은 +90도.
        self.declare_parameter('front_angle_deg', 90.0)
        self.declare_parameter('front_half_width_deg', 15.0)
        self.declare_parameter('yolo_device', 'cpu')     # GPU 여유 있으면 '0'
        self.front_angle = math.radians(self.get_parameter('front_angle_deg').value)
        self.front_half = math.radians(self.get_parameter('front_half_width_deg').value)
        self.yolo_device = self.get_parameter('yolo_device').value

        self.state = WanderState.WAITING
        self.state_start_time = self.get_clock().now()

        self.last_offset = None
        self.last_offset_time = None
        self.front_distance = float('inf')

        self.bridge = CvBridge()
        self.get_logger().info('YOLO 모델 로딩 중...')
        self.model = YOLO('yolov8n.pt')
        self.get_logger().info(f'YOLO 모델 로딩 완료 (device={self.yolo_device})')

        self.create_subscription(Bool, '/wakeword_detected', self._wakeword_callback, 10)

        scan_qos = QoSProfile(reliability=ReliabilityPolicy.BEST_EFFORT,
                              history=HistoryPolicy.KEEP_LAST, depth=10)
        self.create_subscription(LaserScan, '/scan', self._scan_callback, scan_qos)

        image_qos = QoSProfile(reliability=ReliabilityPolicy.BEST_EFFORT,
                               history=HistoryPolicy.KEEP_LAST, depth=1)
        self.create_subscription(Image, '/image_raw', self._image_callback, image_qos,
                                 callback_group=MutuallyExclusiveCallbackGroup())

        self.cmd_vel_pub = self.create_publisher(Twist, '/cmd_vel', 10)
        self.approach_completed_pub = self.create_publisher(
            Bool, '/owner_approach_completed', 10)

        self.create_timer(TICK_PERIOD_SEC, self._tick)
        # 정면 거리 확인용 로그 (2초마다) - 방향 검증 끝나면 지워도 됨
        self.create_timer(2.0, self._log_front)
        self.get_logger().info(
            f'approach_person 준비 완료 (정면={math.degrees(self.front_angle):.0f}deg) '
            f'- 웨이크워드 대기 중')

    def _log_front(self):
        self.get_logger().info(f'front={self.front_distance:.2f} m  state={self.state.name}')

    def _scan_callback(self, msg: LaserScan):
        n = len(msg.ranges)
        if n == 0 or msg.angle_increment == 0.0:
            return
        center = int(round((self.front_angle - msg.angle_min) / msg.angle_increment))
        half = max(1, int(self.front_half / msg.angle_increment))
        valid = []
        for i in range(center - half, center + half + 1):
            r = msg.ranges[i % n]                      # 360도라 wrap-around 허용
            if msg.range_min <= r <= msg.range_max:
                valid.append(r)
        self.front_distance = min(valid) if valid else float('inf')

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
        if self.state != WanderState.SEARCHING:
            return                                     # 탐색 중에만 추론 (CPU 절약)
        frame = self.bridge.imgmsg_to_cv2(msg, desired_encoding='bgr8')
        width = frame.shape[1]
        results = self.model.predict(frame, device=self.yolo_device,
                                     verbose=False, classes=[0])
        boxes = results[0].boxes

        best_idx, best_conf = None, 0.0
        for i in range(len(boxes)):
            conf = float(boxes.conf[i])
            if conf >= MIN_CONFIDENCE and conf > best_conf:
                best_idx, best_conf = i, conf
        if best_idx is None:
            return

        x1, _, x2, _ = boxes.xyxy[best_idx].tolist()
        self.last_offset = ((x1 + x2) / 2.0 - width / 2.0) / (width / 2.0)
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
            self.get_logger().info(
                f'사람 정면 정렬 완료 (offset={offset:+.2f}, front={self.front_distance:.2f}m) '
                f'- 직진 접근 시작')
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
        if self.front_distance <= TARGET_STOP_DISTANCE_M:
            self.get_logger().info(
                f'사람 전방 {TARGET_STOP_DISTANCE_M*100:.0f}cm 접근 완료 '
                f'(실측 {self.front_distance:.2f}m) - 정지')
            self.approach_completed_pub.publish(Bool(data=True))
            self._stop_and_wait()
            return

        # 안전 타임아웃: 실패이므로 완료 신호를 쏘지 않는다 (원본과 달라진 점)
        if self._elapsed() >= APPROACH_SAFETY_TIMEOUT_SEC:
            self.get_logger().warn(
                f'접근 타임아웃 ({APPROACH_SAFETY_TIMEOUT_SEC}s) - 정지 (완료 신호 없음)')
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
    node = ApproachPersonNode()
    executor = MultiThreadedExecutor(num_threads=2)
    executor.add_node(node)
    try:
        executor.spin()
    except KeyboardInterrupt:
        pass
    finally:
        node.cmd_vel_pub.publish(Twist())     # 종료 시 반드시 정지
        executor.shutdown()
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()
