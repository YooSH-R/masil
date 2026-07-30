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

    def wait_until_ready(self, timeout_sec: float = 30.0):
        self.navigator._waitForNodeToActivate('bt_navigator')

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
