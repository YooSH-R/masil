"""
사람 위치 기반 접근 로직 (S15P11A203-209) - 최종 통합
YOLO+라이다로 계산한 사람 좌표를 MoveInterface에 넘겨 실제로 접근한다.

person_locator.py의 좌표 계산 로직 + petbot_nav_interface의 MoveInterface를
하나로 합친 노드.
"""

import math

import rclpy
from cv_bridge import CvBridge
from rclpy.callback_groups import MutuallyExclusiveCallbackGroup
from rclpy.executors import MultiThreadedExecutor
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy
from sensor_msgs.msg import Image, LaserScan
from ultralytics import YOLO

from petbot_nav_interface.move_interface import MoveInterface


CAMERA_HORIZONTAL_FOV_DEG = 52.0
MIN_CONFIDENCE = 0.5
MIN_VALID_DISTANCE = 0.3
MAX_VALID_DISTANCE = 8.0
GOAL_UPDATE_THRESHOLD = 0.3   # 이전 목표랑 이 거리(m) 이상 차이날 때만 새 목표 전송
APPROACH_STOP_DISTANCE = 0.6  # 사람으로부터 이 거리(m)까지만 접근 (너무 붙지 않게)

# petbot.urdf.xacro 기준: camera_link는 base_link/laser_frame보다 x축으로
# base_length/2(=0.15m) 앞에 있음. laser_frame -> camera_link 변환 시 x축만
# 이만큼 빼주면 된다 (두 프레임 모두 회전 없이 축이 정렬돼 있음).
# URDF의 base_length가 바뀌면 이 값도 같이 맞춰야 한다.
CAMERA_X_OFFSET_FROM_LIDAR = 0.15

# 후보 라이다 포인트를 찾을 때 카메라 각도 기준 좌우로 얼마나 넓게 뒤질지,
# 그리고 camera_link로 재투영한 방향이 카메라 각도와 얼마나 가까워야 매칭으로
# 인정할지의 허용 오차.
SEARCH_WINDOW_DEG = 35.0
MATCH_TOLERANCE_DEG = 5.0


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

        # 이미지 콜백(YOLO 추론, 무거움)과 스캔 콜백(가벼움)을 서로 다른 콜백
        # 그룹으로 분리하고 MultiThreadedExecutor로 실행해, YOLO 추론 중에도
        # scan_callback이 지연 없이 실행되어 self.latest_scan이 최신 상태를
        # 유지하도록 한다.
        image_cb_group = MutuallyExclusiveCallbackGroup()
        scan_cb_group = MutuallyExclusiveCallbackGroup()

        self.image_sub = self.create_subscription(
            Image, '/image_raw', self.image_callback, 10,
            callback_group=image_cb_group)
        self.scan_sub = self.create_subscription(
            LaserScan, '/scan', self.scan_callback, lidar_qos,
            callback_group=scan_cb_group)

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
        matched = self.get_person_position(angle, self.latest_scan)
        if matched is None:
            return

        x_laser, y_laser, distance = matched

        # 너무 가까우면(이미 도착) 이동 안 함
        if distance <= APPROACH_STOP_DISTANCE:
            if self.moving:
                self.mover.cancel()
                self.moving = False
                self.get_logger().info(f'사람에게 도착함 (거리={distance:.2f}m) - 정지')
            return

        # 목표점은 "사람 바로 앞(APPROACH_STOP_DISTANCE만큼 못 미쳐서)"으로 설정.
        # 라이다가 실제로 측정한 방향(x_laser, y_laser)을 따라 되돌아오므로
        # 카메라 각도를 다시 쓰지 않는다 (그러면 또 시차 오차가 생김).
        ux = x_laser / distance
        uy = y_laser / distance
        target_distance = distance - APPROACH_STOP_DISTANCE
        goal_x = ux * target_distance
        goal_y = uy * target_distance

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

    def get_person_position(self, camera_angle, scan, window_deg=SEARCH_WINDOW_DEG,
                             tolerance_deg=MATCH_TOLERANCE_DEG):
        """카메라 각도(camera_link 기준)에 대응하는 라이다 포인트를 찾는다.

        라이다는 camera_link보다 뒤쪽(x축 -CAMERA_X_OFFSET_FROM_LIDAR)에 있어서,
        카메라가 본 각도로 라이다 배열을 바로 인덱싱하면 시차만큼 어긋난다.
        대신 camera_angle 주변 넓은 범위의 라이다 포인트들을 laser_frame 좌표로
        복원한 뒤 camera_link 좌표계로 재투영해서, 그 방향이 실제로 camera_angle과
        가까운 포인트만 후보로 인정한다.
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
    node = PersonApproach()
    executor = MultiThreadedExecutor(num_threads=2)
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
