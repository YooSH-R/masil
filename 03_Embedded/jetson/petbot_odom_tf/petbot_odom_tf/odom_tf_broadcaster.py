"""
odom -> base_link TF 브로드캐스터 (S15P11A203-281)

RPi5가 발행하는 /odom(nav_msgs/Odometry, 엔코더 오도메트리)을 구독해
odom->base_link TF를 브로드캐스트한다. start_idle_wander.sh 등에서 쓰던
가짜 identity TF(static_transform_publisher 0 0 0 0 0 0 odom base_link)를
대체한다.

TF 타임스탬프는 msg.header.stamp(RPi5 시계 기준)를 그대로 쓰지 않고 이
노드(Jetson) 자신의 현재 시각을 쓴다. RPi5는 RTC 배터리가 없고 인터넷
NTP도 안 되는 환경이라 재부팅/컨테이너 재시작마다 시계가 몇 초~몇 시간
단위로 어긋나는 일이 반복됐는데, slam_toolbox/Nav2의 tf2 메시지 필터는
스캔(Jetson 시계)과 정확히 시간이 맞는 TF를 요구해서 이 어긋남이 있으면
"Message Filter dropping"/TF_OLD_DATA로 계속 깨졌다. odom 값(위치/속도
숫자)은 RPi5 것을 그대로 쓰되, TF 타임스탬프만 Jetson 시계로 찍으면 두
클럭이 얼마나 어긋나 있든 상관없이 라이다 스캔 등 Jetson 쪽의 다른 TF
발행자들과 항상 시간이 맞아떨어진다 (대신 RPi5->Jetson 네트워크/처리
지연만큼 아주 약간의 지연은 감수한다 - 로봇이 느리게 움직이는 상황에서는
무시할 수준).
"""

from geometry_msgs.msg import TransformStamped
from nav_msgs.msg import Odometry
import rclpy
from rclpy.node import Node
from tf2_ros import TransformBroadcaster


class OdomTfBroadcaster(Node):

    def __init__(self):
        super().__init__('odom_tf_broadcaster')
        self.tf_broadcaster = TransformBroadcaster(self)
        self.odom_sub = self.create_subscription(
            Odometry, '/odom', self.odom_callback, 10)
        self.get_logger().info('odom_tf_broadcaster 시작됨 (/odom 구독 중)')

    def odom_callback(self, msg: Odometry):
        tf = TransformStamped()
        tf.header.stamp = self.get_clock().now().to_msg()
        tf.header.frame_id = msg.header.frame_id
        tf.child_frame_id = msg.child_frame_id
        tf.transform.translation.x = msg.pose.pose.position.x
        tf.transform.translation.y = msg.pose.pose.position.y
        tf.transform.translation.z = msg.pose.pose.position.z
        tf.transform.rotation = msg.pose.pose.orientation
        self.tf_broadcaster.sendTransform(tf)


def main():
    rclpy.init()
    node = OdomTfBroadcaster()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
