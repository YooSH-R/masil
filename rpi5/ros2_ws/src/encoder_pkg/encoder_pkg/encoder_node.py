import rclpy
from rclpy.node import Node
from std_msgs.msg import Int64
from gpiozero import RotaryEncoder

# [수정됨] 좌우 모터 변경에 따라 핀 번호 스왑
LEFT_A = 26
LEFT_B = 21
RIGHT_A = 20
RIGHT_B = 16

class EncoderNode(Node):
    def __init__(self):
        super().__init__('encoder_node')

        # 1. gpiozero 엔코더 객체 생성
        self.encoder_left = RotaryEncoder(a=LEFT_A, b=LEFT_B, max_steps=0)
        self.encoder_right = RotaryEncoder(a=RIGHT_A, b=RIGHT_B, max_steps=0)

        # 2. ROS2 퍼블리셔 생성
        self.pub_left = self.create_publisher(Int64, 'encoder/left_ticks', 10)
        self.pub_right = self.create_publisher(Int64, 'encoder/right_ticks', 10)

        # 3. 🔍 확인용 디버그 로그 스위치 (True: 출력 ON / False: 출력 OFF)
        self.enable_log = True

        # 4. 타이머 생성 (50Hz = 0.02초 주기)
        self.timer_period = 0.02
        self.timer = self.create_timer(self.timer_period, self.timer_callback)

        self.get_logger().info('🚀 [Encoder Node] 엔코더 데이터 퍼블리셔가 시작되었습니다. (50Hz)')

    def timer_callback(self):
        # 틱 데이터 수집
        left_ticks = int(self.encoder_left.steps)
        right_ticks = int(self.encoder_right.steps)

        # 메시지 생성 및 발행
        msg_left = Int64()
        msg_left.data = left_ticks
        self.pub_left.publish(msg_left)

        msg_right = Int64()
        msg_right.data = right_ticks
        self.pub_right.publish(msg_right)

        # =========================================================================
        # 🔍 [확인용 로그 출력 블록]
        # 1) self.enable_log = False 로 설정해서 끄기
        # 2) 또는 이 블록 전체를 주석(#) 처리해서 끄기
        if self.enable_log:
            # ROS2 표준 로거 방식 (권장)
            self.get_logger().info(f' [Ticks] Left: {left_ticks:6d}  |  Right: {right_ticks:6d}')
            
            # 파이썬 기본 print 방식 (필요 시 주석 해제)
            # print(f'[Ticks] Left: {left_ticks:6d}  |  Right: {right_ticks:6d}')
        # =========================================================================

def main(args=None):
    rclpy.init(args=args)
    node = EncoderNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        node.get_logger().info('🛑 엔코더 노드를 종료합니다.')
    finally:
        node.destroy_node()
        rclpy.shutdown()

if __name__ == '__main__':
    main()
