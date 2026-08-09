"""
공통 이동 인터페이스 (S15P11A203-204)
idle배회(-208), 사람 접근(-209) 등이 공통으로 사용하는 이동 래퍼.
Nav2 NavigateToPose 액션을 nav2_simple_commander로 감싸서
"좌표만 넣으면 이동" 수준으로 단순화한다.

wait_until_ready()는 AMCL이 아니라 bt_navigator 활성화만 체크한다.
(SLAM/Cartographer 사용 환경에는 AMCL 노드 자체가 없기 때문)
"""

import math
from nav2_simple_commander.robot_navigator import BasicNavigator, TaskResult
from geometry_msgs.msg import PoseStamped


class MoveInterface:
    def __init__(self, node_name: str = "petbot_move_interface"):
        self.navigator = BasicNavigator(node_name)

    def wait_until_ready(self, timeout_sec: float = 30.0, wait_for_localizer: bool = False):
        """Nav2 스택(costmap, planner, controller)이 active 될 때까지 대기.

        wait_for_localizer=True면 AMCL이 active 될 때까지도 같이 기다린다
        (nav2_simple_commander.waitUntilNav2Active 기본 동작). 지금은 AMCL 없이
        map->odom을 identity 고정 TF로 채우고 있어서(SLAM/AMCL 붙기 전),
        기본값은 False로 두고 bt_navigator만 확인한다 — AMCL이 없는 상태에서
        기본값을 True로 두면 존재하지 않는 amcl/get_state 서비스를 계속 기다리며
        영원히 멈춘다. AMCL을 붙이는 작업(-201)에서 True로 바꿔서 쓰면 된다.
        """
        if wait_for_localizer:
            self.navigator.waitUntilNav2Active()
        else:
            self.navigator._waitForNodeToActivate('bt_navigator')
            self.navigator.info('Nav2 is ready for use! (localizer wait skipped)')

    def move_to(self, x: float, y: float, yaw: float = 0.0, frame_id: str = "map"):
        goal_pose = PoseStamped()
        goal_pose.header.frame_id = frame_id
        goal_pose.header.stamp = self.navigator.get_clock().now().to_msg()
        goal_pose.pose.position.x = x
        goal_pose.pose.position.y = y
        goal_pose.pose.orientation.z = math.sin(yaw / 2.0)
        goal_pose.pose.orientation.w = math.cos(yaw / 2.0)
        self.navigator.goToPose(goal_pose)

    def is_done(self) -> bool:
        return self.navigator.isTaskComplete()

    def get_result(self) -> str:
        result = self.navigator.getResult()
        if result == TaskResult.SUCCEEDED:
            return "SUCCEEDED"
        elif result == TaskResult.CANCELED:
            return "CANCELED"
        elif result == TaskResult.FAILED:
            return "FAILED"
        return "UNKNOWN"

    def cancel(self):
        self.navigator.cancelTask()

    def get_feedback(self):
        return self.navigator.getFeedback()
