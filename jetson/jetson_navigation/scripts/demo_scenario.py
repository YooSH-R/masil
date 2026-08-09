#!/usr/bin/env python3
"""시연 마스터 스크립트.

흐름: 현관(entrance) 자율주행 -> 도착하면 웨이크워드/사람접근 노드 기동
      -> 웨이크워드 대기 -> 감지 시 회전 탐색 -> 전방 50cm 접근 -> 완료.

원본에서 바뀐 점:
  1) 하위 노드를 `ros2 run` 이 아니라 venv 를 source 한 bash 로 실행한다.
     openwakeword 는 ~/wakeword-env, ultralytics(YOLO) 는 ~/yolo-env 에만 깔려
     있어서 `ros2 run` 으로는 ModuleNotFoundError 로 즉사한다.
  2) 사람 접근 노드는 우리가 수정한 approach_person.py 를 쓴다
     (정면 라이다 구간 보정 + 회전 속도 하향 + 타임아웃 시 완료신호 미발행).
  3) 현관 주행에 타임아웃 추가 (실패 시 무한 대기 방지).
  4) 종료 처리에서 미생성 객체 참조로 죽지 않게 정리.

실행: python3 demo_scenario.py            (step1.sh 가 먼저 떠 있어야 함)
"""

import math
import os
import signal
import subprocess
import time

import rclpy
import yaml
from geometry_msgs.msg import PoseStamped
from nav2_simple_commander.robot_navigator import BasicNavigator, TaskResult
from rclpy.node import Node
from std_msgs.msg import Bool

WAYPOINTS_FILE = os.path.expanduser(
    "~/ros_ws/src/jetson_navigation/maps/ver4/waypoints.yaml")
APPROACH_NODE = os.path.expanduser(
    "~/ros_ws/src/jetson_navigation/scripts/approach_person.py")
WAKEWORD_NODE = os.path.expanduser(
    "~/ros2_ws/build/petbot_wakeword/petbot_wakeword/wakeword_node.py")

GOAL_TIMEOUT_SEC = 120.0

WAKEWORD_CMD = (
    "source /opt/ros/humble/setup.bash && "
    "source ~/ros_ws/install/setup.bash && "
    "ros2 run petbot_wakeword wakeword_node"
)
APPROACH_CMD = (
    "source /opt/ros/humble/setup.bash && "
    "source ~/ros_ws/install/setup.bash && "
    f"python3 {APPROACH_NODE}"
)


class DemoMasterNode(Node):
    def __init__(self):
        super().__init__('demo_master_node')
        self.approach_completed = False
        self.create_subscription(
            Bool, '/owner_approach_completed', self._approach_callback, 10)

    def _approach_callback(self, msg: Bool):
        if msg.data:
            self.approach_completed = True


def load_waypoint(path, target_name):
    with open(path) as f:
        data = yaml.safe_load(f)
    for wp in data["waypoints"]:
        if wp["name"] == target_name:
            return wp
    raise ValueError(f"waypoints.yaml 에서 '{target_name}' 을 찾을 수 없습니다.")


def make_pose(navigator, x, y, yaw):
    pose = PoseStamped()
    pose.header.frame_id = "map"
    pose.header.stamp = navigator.get_clock().now().to_msg()
    pose.pose.position.x = float(x)
    pose.pose.position.y = float(y)
    pose.pose.orientation.z = math.sin(float(yaw) / 2.0)
    pose.pose.orientation.w = math.cos(float(yaw) / 2.0)
    return pose


def spawn(cmd):
    """venv 를 source 한 bash 로 노드 실행. 종료 시 자식까지 죽이려고 새 프로세스 그룹."""
    return subprocess.Popen(["bash", "-lc", cmd], preexec_fn=os.setsid)


def kill_group(proc):
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
    except Exception:
        proc.terminate()


def main():
    rclpy.init()
    navigator = None
    master_node = None
    procs = []

    try:
        wp = load_waypoint(WAYPOINTS_FILE, "entrance")
        print(f"\n[설정] 목표: {wp['name']} "
              f"(x={wp['x']}, y={wp['y']}, yaw={wp.get('yaw', 0.0)})")

        navigator = BasicNavigator("demo_scenario_navigator")
        print("\nNav2 준비 대기 중...")
        # waitUntilNav2Active(localizer='amcl') 는 amcl_pose 미수신 시 /initialpose 로
        # (0,0,0) 을 쏴서 위치를 원점으로 리셋해버린다. bt_navigator 만 기다린다.
        navigator._waitForNodeToActivate('bt_navigator')
        print("Nav2 준비 완료\n")

        # ---------- 1단계: 현관 이동 ----------
        print(f"[{wp['name']}] 로 이동 시작...")
        navigator.goToPose(make_pose(navigator, wp['x'], wp['y'], wp.get('yaw', 0.0)))

        start = time.time()
        last_report = 0.0
        while not navigator.isTaskComplete():
            fb = navigator.getFeedback()
            now = time.time()
            if fb and now - last_report > 2.0:
                print(f"    남은 거리 {fb.distance_remaining:.2f} m")
                last_report = now
            if now - start > GOAL_TIMEOUT_SEC:
                print("현관 주행 타임아웃 - 취소")
                navigator.cancelTask()
                break
            time.sleep(0.2)

        if navigator.getResult() != TaskResult.SUCCEEDED:
            print("\n[중단] 현관 주행 실패 - 시연을 중단합니다.")
            return

        print("\n==================================================")
        print(" [1단계 완료] 현관 도착")
        print("==================================================")

        # ---------- 2단계: AI 노드 기동 ----------
        print("\n웨이크워드 노드 시작...")
        procs.append(spawn(WAKEWORD_CMD))
        time.sleep(5)                      # 모델 로딩 + 마이크 스트림 개설 대기

        print("사람 접근 노드 시작 (YOLO 로딩에 시간이 걸립니다)...")
        procs.append(spawn(APPROACH_CMD))
        time.sleep(10)                     # YOLO 로딩 대기

        # ---------- 3단계: 웨이크워드 대기 ----------
        master_node = DemoMasterNode()
        print("\n[준비 완료] 웨이크워드 대기 중... ('마실아' 라고 불러주세요)")

        while rclpy.ok() and not master_node.approach_completed:
            rclpy.spin_once(master_node, timeout_sec=0.1)

        print("\n==================================================")
        print(" [시연 완료] 웨이크워드 -> 사람 탐색 -> 전방 50cm 도달")
        print("==================================================\n")

    except KeyboardInterrupt:
        print("\n[사용자 중단]")
    finally:
        print("\n[정리] 하위 노드 종료 중...")
        for p in procs:
            kill_group(p)
        if master_node is not None:
            master_node.destroy_node()
        if navigator is not None:
            navigator.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()
