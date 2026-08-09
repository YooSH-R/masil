#!/bin/bash
# 터미널 1: 센서 + Nav2 자율주행 스택 (젯슨)
#
# 원본에서 바뀐 점:
#   - ekf_launch.py 제거: EKF 는 파이5 컨테이너에서 이미 돌고 있다.
#     젯슨에서도 띄우면 odom->base_link TF 를 둘이 동시에 발행해 위치가 떨린다.
#   - trap 추가: Ctrl+C 시 백그라운드 노드(라이다/카메라)도 같이 종료.
#     안 그러면 고아 프로세스로 남아 다음 실행 때 중복 노드 문제가 난다.
#   - 라이다 기동 후 Nav2 까지 sleep 을 둬서 /scan 이 먼저 살아있게 함.
#
# 전제: 파이5 컨테이너(rpi5_humble)가 떠 있고 로봇이 home 자리에 있을 것.

source /opt/ros/humble/setup.bash
source ~/ros_ws/install/setup.bash

PIDS=()
cleanup() {
    echo -e "\n[shutdown] 백그라운드 노드 정리 중..."
    kill "${PIDS[@]}" 2>/dev/null
    wait "${PIDS[@]}" 2>/dev/null
    exit 0
}
trap cleanup SIGINT SIGTERM

echo "======== [1/3] YDLidar ========"
ros2 launch ydlidar_ros2_driver ydlidar_launch.py &
PIDS+=($!)
sleep 5

echo "======== [2/3] Camera ========"
ros2 run v4l2_camera v4l2_camera_node --ros-args -p image_size:="[640,480]" &
PIDS+=($!)
sleep 3

echo "======== [3/3] Nav2 (포그라운드) ========"
ros2 launch nav2_bringup bringup_launch.py \
  map:=$HOME/ros_ws/src/jetson_navigation/maps/ver4/map.yaml \
  params_file:=$HOME/ros_ws/src/jetson_navigation/config/nav2_params.yaml \
  use_sim_time:=false
