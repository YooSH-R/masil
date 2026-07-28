"""
사람 위치 기반 접근 로직 - 좌표 변환 부분 (S15P11A203-209)

카메라(YOLO)로 사람을 탐지해 화면 속 좌표(픽셀)를 얻고,
그 방향에 해당하는 라이다 스캔 값에서 실제 거리를 가져와
로봇 기준 (x, y) 좌표를 계산해 발행한다.

개선사항:
  - MIN_VALID_DISTANCE: 이 거리보다 가까운 라이다 값은 가구/잡음으로 간주하고 무시
  - 평균 대신 중앙값(median) 사용 -> 튀는 값(가구 모서리 등)에 덜 민감
"""

import math
import statistics
import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy
from sensor_msgs.msg import Image, LaserScan
from geometry_msgs.msg import PointStamped
from cv_bridge import CvBridge
from ultralytics import YOLO


CAMERA_HORIZONTAL_FOV_DEG = 52.0
MIN_CONFIDENCE = 0.5
MIN_VALID_DISTANCE = 0.3
MAX_VALID_DISTANCE = 8.0


class PersonLocator(Node):
    def __init__(self):
        super().__init__('person_locator')

        self.bridge = CvBridge()
        self.get_logger().info('YOLO 모델 로딩 중...')
        self.model = YOLO('yolov8n.pt')
        self.get_logger().info('YOLO 모델 로딩 완료')

        self.latest_scan = None
        self.image_width = None

        lidar_qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=10
        )

        self.image_sub = self.create_subscription(
            Image, '/image_raw', self.image_callback, 10)
        self.scan_sub = self.create_subscription(
            LaserScan, '/scan', self.scan_callback, lidar_qos)

        self.location_pub = self.create_publisher(
            PointStamped, '/person_location', 10)

        self.get_logger().info('person_locator 노드 시작됨')

    def scan_callback(self, msg):
        self.latest_scan = msg

    def image_callback(self, msg):
        if self.latest_scan is None:
            return

        frame = self.bridge.imgmsg_to_cv2(msg, desired_encoding='bgr8')
        self.image_width = frame.shape[1]

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

        angle = self.pixel_to_angle(center_x_px, self.image_width)
        distance = self.get_range_at_angle(angle, self.latest_scan)

        if distance is None:
            self.get_logger().warn(
                f'각도 {math.degrees(angle):.1f}도 방향에 유효한 라이다 값 없음 '
                f'(가구/잡음으로 필터링 되었거나 데이터 없음)'
            )
            return

        point = PointStamped()
        point.header.frame_id = 'laser_frame'
        point.header.stamp = self.get_clock().now().to_msg()
        point.point.x = distance * math.cos(angle)
        point.point.y = distance * math.sin(angle)
        point.point.z = 0.0

        self.location_pub.publish(point)
        self.get_logger().info(
            f'사람 감지 (conf={conf:.2f}) -> 각도={math.degrees(angle):.1f}도, '
            f'거리={distance:.2f}m -> (x={point.point.x:.2f}, y={point.point.y:.2f})'
        )

    def pixel_to_angle(self, pixel_x, image_width):
        normalized = (pixel_x - image_width / 2.0) / (image_width / 2.0)
        half_fov_rad = math.radians(CAMERA_HORIZONTAL_FOV_DEG / 2.0)
        angle = -normalized * half_fov_rad
        return angle

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
    node = PersonLocator()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
