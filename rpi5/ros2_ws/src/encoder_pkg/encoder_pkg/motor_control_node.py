import math
import time

import rclpy
from rclpy.node import Node
from geometry_msgs.msg import Twist
from nav_msgs.msg import Odometry
from gpiozero import Motor, RotaryEncoder

# Cytron MDD3A: M1A/M1B and M2A/M2B are both PWM inputs (DC-20kHz).
# Truth table: (A=PWM,B=Low)=forward at that duty, (A=Low,B=PWM)=backward,
# (Low,Low)=brake. This is exactly gpiozero.Motor's forward()/backward()/stop().
#
# NOTE (2026-08-04): determined by isolated single-wheel tests (one motor
# channel driven at a time, watching which physical wheel moved and which
# way), since the M1/M2 channel numbers and the encoder A/B connector
# numbers turned out *not* to correspond to the same physical wheel:
#   - M1 channel (GPIO5/6) actually drives the physical LEFT wheel.
#     GPIO5=A drove it backward, so GPIO6=B is left's true forward pin.
#   - M2 channel (GPIO17/27) actually drives the physical RIGHT wheel.
#     GPIO17=A drove it forward correctly.
# The encoder pairing (LEFT=GPIO26/21, RIGHT=GPIO20/16 below) was
# separately confirmed by hand-rotating the physical left wheel and
# watching which encoder counted — that identification is independent of
# the motor-channel mixup above and does not need to change.
LEFT_FORWARD_PIN = 6    # M1B, physical pin 31
LEFT_BACKWARD_PIN = 5   # M1A, physical pin 29
RIGHT_FORWARD_PIN = 17  # M2A, physical pin 11
RIGHT_BACKWARD_PIN = 27 # M2B, physical pin 13

# Encoders (same wiring as encoder_node.py)
LEFT_A = 26
LEFT_B = 21
RIGHT_A = 20
RIGHT_B = 16


class MotorControlNode(Node):
    def __init__(self):
        super().__init__('motor_control_node')

        # Measured 2026-08-04 with calipers/tape on the real robot (previously
        # just copied from Jetson's URDF placeholder: 0.033/0.22).
        # Wheel diameter 65mm -> radius 32.5mm. Wheel separation 230mm.
        self.declare_parameter('wheel_radius_m', 0.0325)
        self.declare_parameter('wheel_separation_m', 0.23)
        # Calibrated 2026-08-04: two independent 5-wheel-rotation trials gave
        # 6485 and 6471 ticks (avg 1295.6/rev) — this is ticks per *wheel*
        # rev, already including the gearmotor's internal reduction ratio.
        self.declare_parameter('encoder_ticks_per_rev', 1296)
        # Calibrated 2026-08-04: 100% PWM, steady-state /wheel_odom twist.linear.x
        # averaged ~0.205 m/s across 33 samples (tight cluster, 0.2033-0.2069).
        self.declare_parameter('max_wheel_speed_mps', 0.205)
        self.declare_parameter('cmd_vel_timeout_ms', 300)
        self.declare_parameter('odom_rate_hz', 30.0)
        self.declare_parameter('odom_frame_id', 'odom')
        self.declare_parameter('base_frame_id', 'base_link')
        # Merged from encoder_pkg's standalone encoder_node.py debug switch.
        self.declare_parameter('debug_log_ticks', False)

        self.wheel_radius = self.get_parameter('wheel_radius_m').value
        self.wheel_separation = self.get_parameter('wheel_separation_m').value
        self.ticks_per_rev = self.get_parameter('encoder_ticks_per_rev').value
        self.max_wheel_speed = self.get_parameter('max_wheel_speed_mps').value
        self.cmd_vel_timeout_s = self.get_parameter('cmd_vel_timeout_ms').value / 1000.0
        self.odom_frame_id = self.get_parameter('odom_frame_id').value
        self.base_frame_id = self.get_parameter('base_frame_id').value
        self.debug_log_ticks = self.get_parameter('debug_log_ticks').value

        self.motor_left = Motor(forward=LEFT_FORWARD_PIN, backward=LEFT_BACKWARD_PIN, pwm=True)
        self.motor_right = Motor(forward=RIGHT_FORWARD_PIN, backward=RIGHT_BACKWARD_PIN, pwm=True)

        self.encoder_left = RotaryEncoder(a=LEFT_A, b=LEFT_B, max_steps=0)
        self.encoder_right = RotaryEncoder(a=RIGHT_A, b=RIGHT_B, max_steps=0)

        self.target_linear_x = 0.0
        self.target_angular_z = 0.0
        self.last_cmd_vel_time = time.monotonic()
        self.watchdog_was_tripped = False

        self.x = 0.0
        self.y = 0.0
        self.theta = 0.0
        self.prev_left_ticks = 0
        self.prev_right_ticks = 0
        self.last_tick_time = time.monotonic()

        self.cmd_vel_sub = self.create_subscription(Twist, '/cmd_vel', self.on_cmd_vel, 10)
        # Raw wheel-encoder odometry. The EKF (robot_localization) fuses this
        # with /imu/data and publishes the actual /odom Jetson subscribes to.
        self.odom_pub = self.create_publisher(Odometry, '/wheel_odom', 10)

        odom_rate_hz = self.get_parameter('odom_rate_hz').value
        self.timer = self.create_timer(1.0 / odom_rate_hz, self.on_timer)

        self.get_logger().info(
            f'motor_control_node up (MDD3A/gpiozero): wheel_r={self.wheel_radius:.3f} '
            f'wheel_sep={self.wheel_separation:.3f} ticks_per_rev={self.ticks_per_rev} '
            f'max_speed={self.max_wheel_speed:.2f}m/s watchdog={self.cmd_vel_timeout_s * 1000:.0f}ms'
        )

    def on_cmd_vel(self, msg: Twist):
        self.target_linear_x = msg.linear.x
        self.target_angular_z = msg.angular.z
        self.last_cmd_vel_time = time.monotonic()

    def on_timer(self):
        now = time.monotonic()
        watchdog_tripped = (now - self.last_cmd_vel_time) > self.cmd_vel_timeout_s
        linear_x = 0.0 if watchdog_tripped else self.target_linear_x
        angular_z = 0.0 if watchdog_tripped else self.target_angular_z

        if watchdog_tripped and not self.watchdog_was_tripped:
            self.get_logger().warn('cmd_vel watchdog tripped — stopping motors')
        self.watchdog_was_tripped = watchdog_tripped

        self.apply_motor_speeds(linear_x, angular_z)
        self.publish_odom()

        if self.debug_log_ticks:
            self.get_logger().info(
                f'[Ticks] Left: {self.encoder_left.steps:6d}  |  '
                f'Right: {self.encoder_right.steps:6d}')

    def apply_motor_speeds(self, linear_x, angular_z):
        v_left = linear_x - angular_z * self.wheel_separation / 2.0
        v_right = linear_x + angular_z * self.wheel_separation / 2.0

        def drive(motor, v_mps):
            mag = min(abs(v_mps) / self.max_wheel_speed, 1.0)
            if mag == 0.0:
                motor.stop()
            elif v_mps >= 0.0:
                motor.forward(mag)
            else:
                motor.backward(mag)

        drive(self.motor_left, v_left)
        drive(self.motor_right, v_right)

    def publish_odom(self):
        now = time.monotonic()
        dt = now - self.last_tick_time
        self.last_tick_time = now
        if dt <= 0.0:
            return

        # Left encoder counts opposite-signed to right for the same physical
        # forward direction (mirrored mounting, like the motor channels) —
        # confirmed 2026-08-04: driving straight gave left_ticks going
        # negative while right_ticks went positive at matching magnitude.
        left_now = -self.encoder_left.steps
        right_now = self.encoder_right.steps
        dleft = left_now - self.prev_left_ticks
        dright = right_now - self.prev_right_ticks
        self.prev_left_ticks = left_now
        self.prev_right_ticks = right_now

        wheel_circumference = 2.0 * math.pi * self.wheel_radius
        dist_left = dleft * wheel_circumference / self.ticks_per_rev
        dist_right = dright * wheel_circumference / self.ticks_per_rev

        v_left = dist_left / dt
        v_right = dist_right / dt
        linear_x = (v_left + v_right) / 2.0
        angular_z = (v_right - v_left) / self.wheel_separation

        d_center = (dist_left + dist_right) / 2.0
        d_theta = (dist_right - dist_left) / self.wheel_separation
        # REP103: x forward, y left, theta CCW-positive.
        self.x += d_center * math.cos(self.theta + d_theta / 2.0)
        self.y += d_center * math.sin(self.theta + d_theta / 2.0)
        self.theta += d_theta

        odom = Odometry()
        odom.header.stamp = self.get_clock().now().to_msg()
        odom.header.frame_id = self.odom_frame_id
        odom.child_frame_id = self.base_frame_id
        odom.pose.pose.position.x = self.x
        odom.pose.pose.position.y = self.y
        odom.pose.pose.orientation.z = math.sin(self.theta / 2.0)
        odom.pose.pose.orientation.w = math.cos(self.theta / 2.0)
        odom.twist.twist.linear.x = linear_x
        odom.twist.twist.angular.z = angular_z
        self.odom_pub.publish(odom)


def main(args=None):
    rclpy.init(args=args)
    node = MotorControlNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.motor_left.stop()
        node.motor_right.stop()
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
