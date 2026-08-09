#!/usr/bin/env python3
"""저장된 웨이포인트로 이동하는 단독 스크립트.

패키지 빌드 불필요. Nav2 설치 시 함께 들어오는 nav2_simple_commander 만 사용한다.

준비:
  1) Nav2(bringup)가 떠 있고, RViz의 2D Pose Estimate 로 초기 위치를 잡아둘 것
  2) waypoints.yaml 준비 (아래 형식)

        waypoints:
          - name: entrance
            x: 0.286
            y: 2.857
            yaw: 0.203      # 라디안, 생략 가능(기본 0.0)

사용:
  cd ~/ros_ws/src/jetson_navigation/launch
  python3 goto.py --list                    # 저장된 지점 목록
  python3 goto.py entrance                  # 해당 지점으로 이동
  python3 goto.py entrance home             # 여러 지점 순서대로 순회
  python3 goto.py --here                    # 현재 위치 좌표만 출력 (웨이포인트 수집용)
  python3 goto.py entrance --waypoints /path/to/waypoints.yaml
"""

import argparse
import math
import sys
import time

import rclpy
import yaml
from geometry_msgs.msg import PoseStamped
from nav2_simple_commander.robot_navigator import BasicNavigator, TaskResult
from tf2_ros import Buffer, TransformListener

DEFAULT_WAYPOINTS = "/home/jetson/ros_ws/src/jetson_navigation/maps/ver4/waypoints.yaml"
GOAL_TIMEOUT_SEC = 120.0


def load_waypoints(path):
    with open(path) as f:
        data = yaml.safe_load(f)
    return {wp["name"]: wp for wp in data["waypoints"]}


def make_pose(navigator, x, y, yaw):
    pose = PoseStamped()
    pose.header.frame_id = "map"
    pose.header.stamp = navigator.get_clock().now().to_msg()
    pose.pose.position.x = float(x)
    pose.pose.position.y = float(y)
    pose.pose.orientation.z = math.sin(float(yaw) / 2.0)
    pose.pose.orientation.w = math.cos(float(yaw) / 2.0)
    return pose


def print_current_pose(navigator):
    """웨이포인트 수집용: map->base_link 를 읽어 yaml 형식으로 출력."""
    buf = Buffer()
    TransformListener(buf, navigator)
    deadline = time.time() + 5.0
    while time.time() < deadline:
        rclpy.spin_once(navigator, timeout_sec=0.2)
        try:
            t = buf.lookup_transform("map", "base_link", rclpy.time.Time())
        except Exception:
            continue
        q = t.transform.rotation
        yaw = 2.0 * math.atan2(q.z, q.w)
        print("\n  - name: <이름을 정하세요>")
        print(f"    x: {t.transform.translation.x:.3f}")
        print(f"    y: {t.transform.translation.y:.3f}")
        print(f"    yaw: {yaw:.3f}\n")
        return True
    print("map->base_link 변환을 못 읽었습니다. AMCL 초기 위치를 먼저 잡으세요.")
    return False


def goto(navigator, name, wp):
    yaw = wp.get("yaw", 0.0)
    print(f"[{name}] ({wp['x']}, {wp['y']}, yaw={yaw}) 로 이동 시작")
    navigator.goToPose(make_pose(navigator, wp["x"], wp["y"], yaw))

    start = time.time()
    last_report = 0.0
    while not navigator.isTaskComplete():
        feedback = navigator.getFeedback()
        now = time.time()
        if feedback and now - last_report > 2.0:      # 2초마다 남은 거리 출력
            print(f"    남은 거리 {feedback.distance_remaining:.2f} m")
            last_report = now
        if now - start > GOAL_TIMEOUT_SEC:
            print(f"[{name}] 타임아웃 - 취소")
            navigator.cancelTask()
            break

    result = navigator.getResult()
    label = {TaskResult.SUCCEEDED: "성공",
             TaskResult.CANCELED: "취소됨",
             TaskResult.FAILED: "실패"}.get(result, "알수없음")
    print(f"[{name}] {label} ({time.time() - start:.1f}s)")
    return result == TaskResult.SUCCEEDED


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("names", nargs="*", help="이동할 웨이포인트 이름(여러 개면 순회)")
    parser.add_argument("--waypoints", default=DEFAULT_WAYPOINTS)
    parser.add_argument("--list", action="store_true", help="저장된 지점 목록 출력")
    parser.add_argument("--here", action="store_true", help="현재 위치를 yaml 형식으로 출력")
    args = parser.parse_args()

    rclpy.init()
    navigator = BasicNavigator("goto_waypoint")

    try:
        if args.here:
            print_current_pose(navigator)
            return

        waypoints = load_waypoints(args.waypoints)

        if args.list or not args.names:
            print(f"\n{args.waypoints} 의 웨이포인트:")
            for name, wp in waypoints.items():
                print(f"  {name:<15} x={wp['x']:>7.3f}  y={wp['y']:>7.3f}  yaw={wp.get('yaw', 0.0):>6.3f}")
            print()
            return

        unknown = [n for n in args.names if n not in waypoints]
        if unknown:
            print(f"모르는 지점: {', '.join(unknown)}  (--list 로 확인)")
            sys.exit(1)

        # BasicNavigator.waitUntilNav2Active(localizer="amcl") 는 amcl_pose 를
        # 아직 못 받았으면 /initialpose 로 (0,0,0) 을 발행해 AMCL 을 원점으로
        # 리셋시킨다. 이미 잡혀 있는 위치를 망가뜨리므로 쓰지 않고,
        # bt_navigator 활성화만 직접 기다린다.
        print("Nav2 준비 대기 중...")
        navigator._waitForNodeToActivate('bt_navigator')
        print("Nav2 준비 완료\n")

        for name in args.names:
            if not goto(navigator, name, waypoints[name]):
                print("중단합니다.")
                break
    except KeyboardInterrupt:
        print("\n사용자 중단 - 목표 취소")
        navigator.cancelTask()
    finally:
        navigator.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
