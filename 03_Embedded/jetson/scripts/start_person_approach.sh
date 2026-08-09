#!/bin/bash
# start_person_approach.sh
# 카메라 + 라이다 + (map->base_link 고정 TF) + Nav2 + person_approach 를
# tmux 세션으로 순서대로 실행
#
# 실행: ./start_person_approach.sh
# 확인: tmux attach -t approach   (창 전환: Ctrl+B 누르고 숫자 0~4)
# 중지: ./stop_person_approach.sh

set -e

SESSION="approach"

tmux kill-session -t $SESSION 2>/dev/null || true

echo "[1/5] 카메라 노드 시작..."
tmux new-session -d -s $SESSION -n camera
tmux send-keys -t $SESSION:camera \
  "source /opt/ros/humble/setup.bash && ros2 run v4l2_camera v4l2_camera_node --ros-args -p image_size:=\"[640,480]\"" C-m

sleep 3

echo "[2/5] 라이다 노드 시작..."
tmux new-window -t $SESSION -n lidar
tmux send-keys -t $SESSION:lidar \
  "cd ~/ydlidar_ros2_ws && source install/setup.bash && ros2 launch ydlidar_ros2_driver ydlidar_launch.py" C-m

sleep 5

echo "[3/5] map->base_link 고정 TF 시작..."
tmux new-window -t $SESSION -n statictf
tmux send-keys -t $SESSION:statictf \
  "source /opt/ros/humble/setup.bash && ros2 run tf2_ros static_transform_publisher 0 0 0 0 0 0 map odom & ros2 run tf2_ros static_transform_publisher 0 0 0 0 0 0 odom base_link & wait" C-m

sleep 2

echo "[4/5] Nav2 bringup 시작..."
tmux new-window -t $SESSION -n nav2
tmux send-keys -t $SESSION:nav2 \
  "source /opt/ros/humble/setup.bash && ros2 launch nav2_bringup navigation_launch.py use_sim_time:=False" C-m

sleep 8

echo "[5/5] person_approach 노드 시작 (yolo-env)..."
tmux new-window -t $SESSION -n approach
tmux send-keys -t $SESSION:approach \
  "source ~/yolo-env/bin/activate && source /opt/ros/humble/setup.bash && source ~/ros2_ws/install/setup.bash && python3 ~/ros2_ws/build/petbot_person_locator/petbot_person_locator/person_approach.py" C-m

echo ""
echo "=========================================="
echo "5개 노드 전부 tmux 세션 'approach'에서 실행 중"
echo ""
echo "상태 확인:  tmux attach -t approach"
echo "창 전환:    Ctrl+B 누르고 손 떼고 숫자 0(camera) 1(lidar) 2(statictf) 3(nav2) 4(approach)"
echo "빠져나오기(계속 실행됨): Ctrl+B 누르고 손 떼고 D"
echo "=========================================="
