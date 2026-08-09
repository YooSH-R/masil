#!/bin/bash
# Jetson: Lidar + Camera + EKF + Nav2 + Wakeword + IdleWander + Demo Scenario All-in-One Master Script
#
# Usage:
#   ./run.sh          # 실행 전용 (빌드 스킵)
#   ./run.sh build    # colcon build 후 전체 실행

WS=~/ros_ws

cd "$WS" || { echo "workspace not found: $WS"; exit 1; }

source /opt/ros/humble/setup.bash

# 1. 선택적 빌드
if [ "${1:-}" = "build" ]; then
    echo "======== [1/5] colcon build ========"
    colcon build --symlink-install || { echo "BUILD FAILED — not launching."; exit 1; }
fi

echo "======== [2/5] source install ========"
source install/setup.bash

# 프로세스 단체 종료 트랩 설정
PIDS=()
cleanup() {
    echo -e "\n[shutdown] 모든 ROS 2 백그라운드 노드 종료 중..."
    for pid in "${PIDS[@]}"; do
        kill "$pid" 2>/dev/null
    done
    wait "${PIDS[@]}" 2>/dev/null
    echo "[shutdown] 모든 노드가 안전하게 정지되었습니다."
    exit 0
}
trap cleanup SIGINT SIGTERM

echo "======== [3/5] 센서 및 자율주행(Nav2) 런칭 ========"

# 1) 라이다 런칭
echo " -> [1/4] YDLidar 시작..."
ros2 launch ydlidar_ros2_driver ydlidar_launch.py &
PIDS+=($!)

# 2) 카메라 런칭
echo " -> [2/4] v4l2 카메라 시작..."
ros2 run v4l2_camera v4l2_camera_node --ros-args -p image_size:="[640,480]" &
PIDS+=($!)

# 3) EKF 런칭
echo " -> [3/4] EKF 시작..."
ros2 launch jetson_navigation ekf_launch.py &
PIDS+=($!)

# 4) Nav2 Bringup 런칭 (실제 세팅 명령어 적용)
echo " -> [4/4] Nav2 Bringup 시작..."
ros2 launch nav2_bringup bringup_launch.py \
  map:=$HOME/ros_ws/src/jetson_navigation/maps/ver4/map.yaml \
  params_file:=$HOME/ros_ws/src/jetson_navigation/config/nav2_params.yaml \
  use_sim_time:=false &
PIDS+=($!)

echo "Nav2 및 백그라운드 노드가 완전히 켜질 때까지 8초 대기..."
sleep 8

echo "======== [4/5] AI & 웨이크워드 노드 런칭 ========"

# 1) 웨이크워드 음성 인식 노드 (오디오 장치 초기화 2초 대기)
echo " -> [1/2] Wakeword 노드 시작..."
ros2 run petbot_wakeword wakeword_node &
PIDS+=($!)
sleep 2

# 2) 사람 탐색 & 50cm 접근 노드 (idle_wander2)
echo " -> [2/2] Idle Wander 2 노드 시작..."
ros2 run petbot_idle_behavior idle_wander2 &
PIDS+=($!)
sleep 3

echo "=================================================="
echo " 모든 백그라운드 노드가 정상 런칭되었습니다."
echo " 마스터 시연 스크립트(demo_scenario.py)를 시작합니다."
echo " (중단하려면 언제든 Ctrl+C를 누르세요)"
echo "=================================================="

# 🎯 demo_scenario.py 파일 위치에 맞게 수정!
python3 demo_scenario.py

# 시연 종료 후 백그라운드 프로세스 자동 정리
cleanup
