"""
사람 위치 기반 접근 로직 (S15P11A203-209) - 최종 통합
YOLO+라이다로 계산한 사람 좌표를 MoveInterface에 넘겨 실제로 접근한다.

person_locator.py의 좌표 계산 로직 + petbot_nav_interface의 MoveInterface를
하나로 합친 노드.
"""

import math
import statistics

import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy
from sensor_msgs.msg import Image, LaserScan
from cv_bridge import CvBridge
from ultralytics import YOLO

from petbot_nav_interface.move_interface import MoveInterface


CAMERA_HORIZONTAL_FOV_DEG = 52.0
MIN_CONFIDENCE = 0.5
MIN_VALID_DISTANCE = 0.3
MAX_VALID_DISTANCE = 8.0
GOAL_UPDATE_THRESHOLD = 0.3   # 이전 목표랑 이 거리(m) 이상 차이날 때만 새 목표 전송
APPROACH_STOP_DISTANCE = 0.6  # 사람으로부터 이 거리(m)까지만 접근 (너무 붙지 않게)


class PersonApproach(Node):
    def __init__(self):
        super().__init__('person_approach')

        self.bridge = CvBridge()
        self.get_logger().info('YOLO 모델 로딩 중...')
        self.model = YOLO('yolov8n.pt')
        self.get_logger().info('YOLO 모델 로딩 완료')

        self.latest_scan = None
        self.last_goal = None       # (x, y) - base_link 기준 마지막 전송 목표
        self.moving = False

        lidar_qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=10
        )

        self.image_sub = self.create_subscription(
            Image, '/image_raw', self.image_callback, 10)
        self.scan_sub = self.create_subscription(
            LaserScan, '/scan', self.scan_callback, lidar_qos)

        self.mover = MoveInterface('person_approach_mover')
        self.get_logger().info('Nav2 준비 대기 중...')
        self.mover.wait_until_ready()
        self.mover_ready = True
        self.get_logger().info('Nav2 준비 완료 - 이제 사람을 감지하면 접근합니다')

        self.get_logger().info('person_approach 노드 시작됨')

    def scan_callback(self, msg):
        self.latest_scan = msg

    def image_callback(self, msg):
        if self.latest_scan is None or not self.mover_ready:
            return

        # 이전 목표로 이동 중이면, 완료될 때까지 새 목표 계산은 계속하되 전송은 보류
        frame = self.bridge.imgmsg_to_cv2(msg, desired_encoding='bgr8')
        image_width = frame.shape[1]

        results = self.model.predict(frame, device=0, verbose=False, classes=[0])
        boxes = results[0].boxes
        if len(boxes) == 0:
            return

        best_idx = int(boxes.conf.argmax())
        conf = float(boxes.conf[best_idx])
        if conf < MIN_CONFIDENCE:
            return

        x1, y1, x2, y2 = boxes.xyxy[best_idx].tolist()
        center_x_px = (x1 + x2) / 2.0

        angle = self.pixel_to_angle(center_x_px, image_width)
        distance = self.get_range_at_angle(angle, self.latest_scan)
        if distance is None:
            return

        # 너무 가까우면(이미 도착) 이동 안 함
        if distance <= APPROACH_STOP_DISTANCE:
            if self.moving:
                self.mover.cancel()
                self.moving = False
                self.get_logger().info(f'사람에게 도착함 (거리={distance:.2f}m) - 정지')
            return

        # 목표점은 "사람 바로 앞(APPROACH_STOP_DISTANCE만큼 못 미쳐서)"으로 설정
        target_distance = distance - APPROACH_STOP_DISTANCE
        goal_x = target_distance * math.cos(angle)
        goal_y = target_distance * math.sin(angle)

        if self._should_send_new_goal(goal_x, goal_y):
            self.mover.move_to(goal_x, goal_y, frame_id='base_link')
            self.last_goal = (goal_x, goal_y)
            self.moving = True
            self.get_logger().info(
                f'사람 감지 (conf={conf:.2f}, 거리={distance:.2f}m) '
                f'-> 목표 전송 (x={goal_x:.2f}, y={goal_y:.2f})'
            )

    def _should_send_new_goal(self, x, y):
        if self.last_goal is None:
            return True
        dx = x - self.last_goal[0]
        dy = y - self.last_goal[1]
        return math.hypot(dx, dy) > GOAL_UPDATE_THRESHOLD

    def pixel_to_angle(self, pixel_x, image_width):
        normalized = (pixel_x - image_width / 2.0) / (image_width / 2.0)
        half_fov_rad = math.radians(CAMERA_HORIZONTAL_FOV_DEG / 2.0)
        return -normalized * half_fov_rad

    def get_range_at_angle(self, angle, scan, window=3):
        if angle < scan.angle_min or angle > scan.angle_max:
            return None
        idx = int(round((angle - scan.angle_min) / scan.angle_increment))
        n = len(scan.ranges)
        valid_ranges = []
        for offset in range(-window, window + 1):
            i = idx + offset
            if 0 <= i < n:
                r = scan.ranges[i]
                if MIN_VALID_DISTANCE <= r <= min(scan.range_max, MAX_VALID_DISTANCE):
                    valid_ranges.append(r)
        if not valid_ranges:
            return None
        return statistics.median(valid_ranges)


def main():
    rclpy.init()
    node = PersonApproach()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
