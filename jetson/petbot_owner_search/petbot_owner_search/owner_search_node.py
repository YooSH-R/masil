"""
웨이크워드 -> 제자리 회전하며 사람 탐색 -> 최근접 사람에게 접근

/wakeword_detected(Bool)에서 True를 받으면:
  1. 제자리 회전(cmd_vel angular.z)하며 카메라+라이다로 사람을 찾는다.
  2. 한 프레임에 여러 명이 보이면 라이다로 거리까지 계산해 가장 가까운 사람을 고른다.
     (ReSpeaker Lite에 방향추정(DOA) 기능이 없어서 "누가 불렀는지"는 알 수 없다 -
     "가까운 사람일 가능성이 높다"는 현실적 타협으로 최근접 사람을 선택한다.)
  3. 찾으면 회전을 멈추고 MoveInterface로 그 사람 앞(APPROACH_STOP_DISTANCE)까지 이동한다.
  4. ROTATE_TIMEOUT_SEC 안에 못 찾으면 포기하고 대기 상태로 복귀한다.

카메라-라이다 시차보정 로직은 person_approach.py와 동일하다. 차이는 거기는
"신뢰도 1등 사람 1명"만 보는 반면, 여기는 "화면에 보이는 모든 사람 중 최근접"을 고른다는 것.

주의: idle_wander.py(PATROL/CHECK_OWNER 등)와 별개 노드로 떠 있어서, 둘 다
MoveInterface/cmd_vel을 건드릴 수 있다. 지금은 서로 조율하는 로직이 없으니
idle_wander가 PATROL 중일 때 웨이크워드가 겹치면 두 노드가 동시에 이동 목표를
보낼 수 있다는 걸 알고 있을 것 (당장은 별도 티켓으로 남겨두고 손대지 않음).
"""

import math

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

from petbot_nav_interface.move_interface import MoveInterface


CAMERA_HORIZONTAL_FOV_DEG = 52.0
MIN_CONFIDENCE = 0.5
MIN_VALID_DISTANCE = 0.3
MAX_VALID_DISTANCE = 8.0
APPROACH_STOP_DISTANCE = 0.6

# petbot_person_locator/person_approach.py와 동일 (URDF 기준 camera_link 오프셋)
CAMERA_X_OFFSET_FROM_LIDAR = 0.15
SEARCH_WINDOW_DEG = 35.0
MATCH_TOLERANCE_DEG = 5.0

ROTATE_ANGULAR_SPEED = 0.5   # rad/s
ROTATE_TIMEOUT_SEC = 15.0    # 2*pi/0.5 ~= 12.6s 한 바퀴 + 여유


class OwnerSearch(Node):

    def __init__(self):
        super().__init__('owner_search')

        self.bridge = CvBridge()
        self.get_logger().info('YOLO 모델 로딩 중...')
        self.model = YOLO('yolov8n.pt')
        self.get_logger().info('YOLO 모델 로딩 완료')

        self.latest_scan = None
        self.searching = False
        self.search_start_time = None

        lidar_qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=10)

        wakeword_cb_group = MutuallyExclusiveCallbackGroup()
        image_cb_group = MutuallyExclusiveCallbackGroup()
        scan_cb_group = MutuallyExclusiveCallbackGroup()

        self.wakeword_sub = self.create_subscription(
            Bool, '/wakeword_detected', self.wakeword_callback, 10,
            callback_group=wakeword_cb_group)
        self.image_sub = self.create_subscription(
            Image, '/image_raw', self.image_callback, 10,
            callback_group=image_cb_group)
        self.scan_sub = self.create_subscription(
            LaserScan, '/scan', self.scan_callback, lidar_qos,
            callback_group=scan_cb_group)

        self.cmd_vel_pub = self.create_publisher(Twist, '/cmd_vel', 10)

        self.mover = MoveInterface('owner_search_mover')
        self.get_logger().info('Nav2 준비 대기 중...')
        self.mover.wait_until_ready()
        self.get_logger().info('Nav2 준비 완료 - 웨이크워드 대기 중')

        self.rotate_timer = self.create_timer(0.1, self._rotate_tick)

    def wakeword_callback(self, msg: Bool):
        if not msg.data:
            return
        if self.searching:
            self.get_logger().info('이미 탐색 중이라 웨이크워드 무시')
            return
        self.get_logger().info('웨이크워드 감지 - 제자리 회전하며 사람 탐색 시작')
        self.searching = True
        self.search_start_time = self.get_clock().now()

    def scan_callback(self, msg):
        self.latest_scan = msg

    def _rotate_tick(self):
        if not self.searching:
            return
        elapsed = (self.get_clock().now() - self.search_start_time).nanoseconds / 1e9
        if elapsed >= ROTATE_TIMEOUT_SEC:
            self.get_logger().info('한 바퀴 다 돌았는데 사람 못 찾음 - 탐색 포기')
            self._stop_rotation()
            return
        twist = Twist()
        twist.angular.z = ROTATE_ANGULAR_SPEED
        self.cmd_vel_pub.publish(twist)

    def _stop_rotation(self):
        self.searching = False
        self.cmd_vel_pub.publish(Twist())

    def image_callback(self, msg):
        if not self.searching or self.latest_scan is None:
            return

        frame = self.bridge.imgmsg_to_cv2(msg, desired_encoding='bgr8')
        image_width = frame.shape[1]

        results = self.model.predict(frame, device=0, verbose=False, classes=[0])
        boxes = results[0].boxes
        if len(boxes) == 0:
            return

        nearest = None  # (x_laser, y_laser, distance, conf)
        for i in range(len(boxes)):
            conf = float(boxes.conf[i])
            if conf < MIN_CONFIDENCE:
                continue
            x1, y1, x2, y2 = boxes.xyxy[i].tolist()
            center_x_px = (x1 + x2) / 2.0
            angle = self.pixel_to_angle(center_x_px, image_width)
            matched = self.get_person_position(angle, self.latest_scan)
            if matched is None:
                continue
            x_laser, y_laser, distance = matched
            if nearest is None or distance < nearest[2]:
                nearest = (x_laser, y_laser, distance, conf)

        if nearest is None:
            return

        x_laser, y_laser, distance, conf = nearest
        self.get_logger().info(
            f'사람 발견 (거리={distance:.2f}m, conf={conf:.2f}) - 회전 정지, 접근 시작')
        self._stop_rotation()
        self._approach(x_laser, y_laser, distance)

    def _approach(self, x_laser, y_laser, distance):
        if distance <= APPROACH_STOP_DISTANCE:
            self.get_logger().info(f'이미 충분히 가까움 (거리={distance:.2f}m) - 접근 생략')
            return
        ux, uy = x_laser / distance, y_laser / distance
        target_distance = distance - APPROACH_STOP_DISTANCE
        goal_x, goal_y = ux * target_distance, uy * target_distance
        self.mover.move_to(goal_x, goal_y, frame_id='base_link')
        self.get_logger().info(f'목표 전송 (x={goal_x:.2f}, y={goal_y:.2f}, frame=base_link)')

    def pixel_to_angle(self, pixel_x, image_width):
        normalized = (pixel_x - image_width / 2.0) / (image_width / 2.0)
        half_fov_rad = math.radians(CAMERA_HORIZONTAL_FOV_DEG / 2.0)
        return -normalized * half_fov_rad

    def get_person_position(self, camera_angle, scan, window_deg=SEARCH_WINDOW_DEG,
                             tolerance_deg=MATCH_TOLERANCE_DEG):
        """카메라 각도(camera_link 기준)에 대응하는 라이다 포인트를 찾는다.

        person_approach.py의 동명 메서드와 동일한 카메라-라이다 시차보정 로직
        (자세한 설명은 그쪽 docstring 참고).
        """
        idx_center = int(round((camera_angle - scan.angle_min) / scan.angle_increment))
        idx_window = max(1, int(math.radians(window_deg) / scan.angle_increment))
        tolerance_rad = math.radians(tolerance_deg)
        n = len(scan.ranges)

        candidates = []
        for i in range(idx_center - idx_window, idx_center + idx_window + 1):
            if not (0 <= i < n):
                continue
            r = scan.ranges[i]
            if not (MIN_VALID_DISTANCE <= r <= min(scan.range_max, MAX_VALID_DISTANCE)):
                continue

            ray_angle = scan.angle_min + i * scan.angle_increment
            x_laser = r * math.cos(ray_angle)
            y_laser = r * math.sin(ray_angle)

            x_cam = x_laser - CAMERA_X_OFFSET_FROM_LIDAR
            y_cam = y_laser
            bearing_from_camera = math.atan2(y_cam, x_cam)

            if abs(bearing_from_camera - camera_angle) <= tolerance_rad:
                candidates.append((r, x_laser, y_laser))

        if not candidates:
            return None

        candidates.sort(key=lambda c: c[0])
        r, x_laser, y_laser = candidates[len(candidates) // 2]
        return x_laser, y_laser, r


def main():
    rclpy.init()
    node = OwnerSearch()
    executor = MultiThreadedExecutor(num_threads=3)
    executor.add_node(node)
    try:
        executor.spin()
    except KeyboardInterrupt:
        pass
    finally:
        executor.shutdown()
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
