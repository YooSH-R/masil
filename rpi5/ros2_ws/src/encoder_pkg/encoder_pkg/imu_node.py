import math

import board
import busio
import adafruit_bno055
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import Imu

DEG_TO_RAD = math.pi / 180.0


class ImuNode(Node):
    def __init__(self):
        super().__init__('imu_node')

        self.declare_parameter('frame_id', 'imu_link')
        self.declare_parameter('publish_rate_hz', 30.0)
        self.frame_id = self.get_parameter('frame_id').value

        i2c = busio.I2C(board.SCL, board.SDA)
        self.sensor = adafruit_bno055.BNO055_I2C(i2c)

        self.imu_pub = self.create_publisher(Imu, '/imu/data', 10)

        rate_hz = self.get_parameter('publish_rate_hz').value
        self.timer = self.create_timer(1.0 / rate_hz, self.on_timer)

        self.get_logger().info(f'imu_node up (BNO055 @ 0x28), publishing /imu/data at {rate_hz}Hz')

    def on_timer(self):
        # The RPi's I2C controller doesn't fully support the clock stretching
        # the BNO055 relies on, so occasional OSError/RuntimeError on a read
        # is expected in normal operation -- log and skip this cycle rather
        # than letting it propagate up and kill the node.
        try:
            quat = self.sensor.quaternion  # (w, x, y, z), None entries if not ready
            gyro = self.sensor.gyro  # deg/s
            accel = self.sensor.linear_acceleration  # m/s^2, gravity-compensated
        except (OSError, RuntimeError) as e:
            self.get_logger().warn(f'BNO055 I2C read failed, skipping cycle: {e}',
                                    throttle_duration_sec=2.0)
            return

        if quat is None or None in quat:
            return

        msg = Imu()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = self.frame_id

        msg.orientation.w = quat[0]
        msg.orientation.x = quat[1]
        msg.orientation.y = quat[2]
        msg.orientation.z = quat[3]
        # Engineering estimates from BNO055 datasheet noise characteristics,
        # not a measured calibration -- fine-tune once real noise data is
        # available. Never leave these at 0: robot_localization's EKF reads
        # zero covariance as "this measurement is exact", which starves out
        # every other input on that channel.
        msg.orientation_covariance = [
            0.01, 0.0, 0.0,
            0.0, 0.01, 0.0,
            0.0, 0.0, 0.01,
        ]

        if gyro is not None and None not in gyro:
            msg.angular_velocity.x = gyro[0] * DEG_TO_RAD
            msg.angular_velocity.y = gyro[1] * DEG_TO_RAD
            msg.angular_velocity.z = gyro[2] * DEG_TO_RAD
        msg.angular_velocity_covariance = [
            0.0004, 0.0, 0.0,
            0.0, 0.0004, 0.0,
            0.0, 0.0, 0.0004,
        ]

        if accel is not None and None not in accel:
            msg.linear_acceleration.x = accel[0]
            msg.linear_acceleration.y = accel[1]
            msg.linear_acceleration.z = accel[2]
        msg.linear_acceleration_covariance = [
            0.017, 0.0, 0.0,
            0.0, 0.017, 0.0,
            0.0, 0.0, 0.017,
        ]

        self.imu_pub.publish(msg)


def main(args=None):
    rclpy.init(args=args)
    node = ImuNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
