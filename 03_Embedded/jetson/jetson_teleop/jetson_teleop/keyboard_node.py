#!/usr/bin/env python3
"""WASD keyboard teleop — continuous-publish (latching) version.

Why this structure: the old node published /cmd_vel only on key events,
so the stream was hostage to OS key-repeat timing (first repeat comes
~500ms after press). The Pi-side watchdog (300ms) fired inside that gap
-> lurch, stop, restart. Here a 10Hz timer publishes the CURRENT target
no matter what; key presses merely change the target.

Controls (latching — no need to hold keys):
    w / s : forward / backward   (press again = keep going)
    a / d : turn left / right
    w+a etc: arc (press w then a — turning adds onto current linear)
    space : stop
    + / - : speed scale
    Ctrl+C: quit (publishes stop first)

Safety: if this node dies or the terminal closes, publishing stops and
the Pi watchdog halts the motors within 300ms — watchdog is back to
being a link-loss failsafe, not the everyday stop mechanism.
"""

import select
import sys
import termios
import tty

import rclpy
from geometry_msgs.msg import Twist
from rclpy.node import Node

LIN = 0.12   # m/s
ANG = 0.25   # rad/s
RATE = 10.0  # Hz — comfortably faster than the Pi 300ms watchdog


class KeyboardTeleop(Node):
    def __init__(self):
        super().__init__('jetson_keyboard_teleop')
        self.pub = self.create_publisher(Twist, 'cmd_vel', 10)
        self.target = Twist()
        self.scale = 1.0
        # Publishing lives on this timer — decoupled from key events.
        self.create_timer(1.0 / RATE, self.publish_target)

    def publish_target(self):
        self.pub.publish(self.target)

    def handle_key(self, key):
        t = self.target
        if key == 'w':
            t.linear.x = LIN * self.scale
        elif key == 's':
            t.linear.x = -LIN * self.scale
        elif key == 'a':
            t.angular.z = ANG * self.scale
        elif key == 'd':
            t.angular.z = -ANG * self.scale
        elif key == ' ':
            t.linear.x = 0.0
            t.angular.z = 0.0
        elif key in ('+', '='):
            self.scale = min(2.0, self.scale + 0.1)
            print(f'\r[scale {self.scale:.1f}]', end='', flush=True)
        elif key in ('-', '_'):
            self.scale = max(0.1, self.scale - 0.1)
            print(f'\r[scale {self.scale:.1f}]', end='', flush=True)

    def stop(self):
        self.target = Twist()
        self.pub.publish(self.target)


def get_key(settings, timeout=0.05):
    tty.setraw(sys.stdin.fileno())
    rlist, _, _ = select.select([sys.stdin], [], [], timeout)
    key = sys.stdin.read(1) if rlist else ''
    termios.tcsetattr(sys.stdin, termios.TCSADRAIN, settings)
    return key


def main(args=None):
    settings = termios.tcgetattr(sys.stdin)
    rclpy.init(args=args)
    node = KeyboardTeleop()

    print('====================================')
    print(' 젯슨 텔레옵 (래칭 모드)')
    print(' [W/S] 전진/후진  [A/D] 좌/우회전')
    print(' [Space] 정지     [+/-] 속도')
    print(' 누르면 계속 유지됩니다. Ctrl+C 종료')
    print('====================================')

    try:
        while rclpy.ok():
            key = get_key(settings)
            if key == '\x03':          # Ctrl+C
                break
            if key:
                node.handle_key(key)
            rclpy.spin_once(node, timeout_sec=0.0)  # run the publish timer
    finally:
        node.stop()
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, settings)
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()