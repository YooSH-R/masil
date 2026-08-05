#!/bin/bash
# start_idle_wander.sh
# 카메라 + 라이다 + (map->odom 고정 TF, odom->base_link 실제 TF) + Nav2 +
# person_locator(항상 켜져있는 사람 감지 서비스) + idle_wander 를
# tmux 세션으로 순서대로 실행
#
# 실행: ./start_idle_wander.sh
# 확인: tmux attach -t idle   (창 전환: Ctrl+B 누르고 숫자 0~5)
# 중지: ./stop_idle_wander.sh

set -e

SESSION="idle"

tmux kill-session -t $SESSION 2>/dev/null || true

echo "[1/6] 카메라 노드 시작..."
tmux new-session -d -s $SESSION -n camera
tmux send-keys -t $SESSION:camera \
  "source /opt/ros/humble/setup.bash && ros2 run v4l2_camera v4l2_camera_node --ros-args -p image_size:=\"[640,480]\"" C-m

sleep 3

echo "[2/6] 라이다 노드 시작..."
tmux new-window -t $SESSION -n lidar
tmux send-keys -t $SESSION:lidar \
  "cd ~/ydlidar_ros2_ws && source install/setup.bash && ros2 launch ydlidar_ros2_driver ydlidar_launch.py" C-m

sleep 5

echo "[3/7] map->odom 고정 TF 시작 (SLAM 지도 없는 테스트용 identity TF, AMCL 붙기 전까지 임시)..."
tmux new-window -t $SESSION -n statictf
tmux send-keys -t $SESSION:statictf \
  "source /opt/ros/humble/setup.bash && ros2 run tf2_ros static_transform_publisher 0 0 0 0 0 0 map odom" C-m

sleep 2

echo "[4/7] odom->base_link TF 브로드캐스터 시작 (RPi5 /odom 구독, 실제 오도메트리)..."
tmux new-window -t $SESSION -n odomtf
tmux send-keys -t $SESSION:odomtf \
  "source /opt/ros/humble/setup.bash && source ~/ros2_ws/install/setup.bash && ros2 run petbot_odom_tf odom_tf_broadcaster" C-m

sleep 2

echo "[5/7] Nav2 bringup 시작..."
tmux new-window -t $SESSION -n nav2
tmux send-keys -t $SESSION:nav2 \
  "source /opt/ros/humble/setup.bash && ros2 launch nav2_bringup navigation_launch.py use_sim_time:=False" C-m

sleep 8

echo "[6/7] person_locator 시작 (yolo-env, /person_location 상시 발행)..."
tmux new-window -t $SESSION -n locator
tmux send-keys -t $SESSION:locator \
  "source ~/yolo-env/bin/activate && source /opt/ros/humble/setup.bash && source ~/ros2_ws/install/setup.bash && python3 ~/ros2_ws/build/petbot_person_locator/petbot_person_locator/person_locator.py" C-m

sleep 3

echo "[7/7] idle_wander 시작 (venv 불필요, 시스템 python3)..."
tmux new-window -t $SESSION -n wander
tmux send-keys -t $SESSION:wander \
  "source /opt/ros/humble/setup.bash && source ~/ros2_ws/install/setup.bash && python3 ~/ros2_ws/build/petbot_idle_behavior/petbot_idle_behavior/idle_wander.py" C-m

echo ""
echo "=========================================="
echo "7개 노드 전부 tmux 세션 'idle'에서 실행 중"
echo ""
echo "상태 확인:  tmux attach -t idle"
echo "창 전환:    Ctrl+B 누르고 손 떼고 숫자 0(camera) 1(lidar) 2(statictf) 3(odomtf) 4(nav2) 5(locator) 6(wander)"
echo "빠져나오기(계속 실행됨): Ctrl+B 누르고 손 떼고 D"
echo "=========================================="
