"""
odom -> base_link TF 브로드캐스터 (S15P11A203-281)

RPi5가 발행하는 /odom(nav_msgs/Odometry, 엔코더 오도메트리)을 구독해
odom->base_link TF를 브로드캐스트한다. start_idle_wander.sh 등에서 쓰던
가짜 identity TF(static_transform_publisher 0 0 0 0 0 0 odom base_link)를
대체한다.
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
        tf.header.stamp = msg.header.stamp
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
