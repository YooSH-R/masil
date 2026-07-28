"""
공통 이동 인터페이스 (S15P11A203-204)
idle배회(-208), 사람 접근(-209) 등이 공통으로 사용하는 이동 래퍼.
Nav2 NavigateToPose 액션을 nav2_simple_commander로 감싸서
"좌표만 넣으면 이동" 수준으로 단순화한다.
"""

from nav2_simple_commander.robot_navigator import BasicNavigator, TaskResult
from geometry_msgs.msg import PoseStamped
import rclpy
from rclpy.duration import Duration


class MoveInterface:
    """
    사용 예:
        mover = MoveInterface()
        mover.wait_until_ready()
        mover.move_to(1.5, 0.8)          # x=1.5m, y=0.8m 로 이동
        while not mover.is_done():
            ...  # 다른 작업 하면서 대기 가능
        result = mover.get_result()       # SUCCEEDED / CANCELED / FAILED
    """

    def __init__(self, node_name: str = "petbot_move_interface"):
        self.navigator = BasicNavigator(node_name)

    def wait_until_ready(self, timeout_sec: float = 30.0):
        """Nav2 스택(costmap, planner, controller)이 active 될 때까지 대기"""
        self.navigator.waitUntilNav2Active()

    def move_to(self, x: float, y: float, yaw: float = 0.0, frame_id: str = "map"):
        """
        지정 좌표로 이동 목표 전송 (논블로킹 — 바로 리턴됨)
        yaw: 최종 도착 시 바라볼 방향 (라디안)
        """
        goal_pose = PoseStamped()
        goal_pose.header.frame_id = frame_id
        goal_pose.header.stamp = self.navigator.get_clock().now().to_msg()
        goal_pose.pose.position.x = x
        goal_pose.pose.position.y = y

        # yaw(라디안) → quaternion 변환 (2D 평면 이동이므로 z축 회전만 고려)
        import math
        goal_pose.pose.orientation.z = math.sin(yaw / 2.0)
        goal_pose.pose.orientation.w = math.cos(yaw / 2.0)

        self.navigator.goToPose(goal_pose)

    def is_done(self) -> bool:
        """이동이 끝났는지(성공/실패/취소 여부와 무관하게) 확인"""
        return self.navigator.isTaskComplete()

    def get_result(self) -> str:
        """이동 완료 후 결과 확인: 'SUCCEEDED' | 'CANCELED' | 'FAILED' | 'UNKNOWN'"""
        result = self.navigator.getResult()
        if result == TaskResult.SUCCEEDED:
            return "SUCCEEDED"
        elif result == TaskResult.CANCELED:
            return "CANCELED"
        elif result == TaskResult.FAILED:
            return "FAILED"
        return "UNKNOWN"

    def cancel(self):
        """진행 중인 이동 취소 (예: 사람이 갑자기 나타나서 idle배회 중단할 때)"""
        self.navigator.cancelTask()

    def get_feedback(self):
        """이동 중 진행상황(남은 거리 등) 확인 — 필요시 사용"""
        return self.navigator.getFeedback()
