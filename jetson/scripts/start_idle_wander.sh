#!/bin/bash
# start_idle_wander.sh
# 카메라 + 라이다 + (slam_toolbox 실주행 SLAM, odom->base_link 실제 TF) + Nav2 +
# person_locator(항상 켜져있는 사람 감지 서비스) + wakeword_node(웨이크워드 감지) +
# owner_search(웨이크워드 -> 회전탐색 -> 최근접 사람 접근) + idle_wander 를
# tmux 세션으로 순서대로 실행
#
# 실행: ./start_idle_wander.sh
# 확인: tmux attach -t idle   (창 전환: Ctrl+B 누르고 숫자 0~8)
# 중지: ./stop_idle_wander.sh

set -e

SESSION="idle"

tmux kill-session -t $SESSION 2>/dev/null || true

echo "[1/9] 카메라 노드 시작..."
tmux new-session -d -s $SESSION -n camera
tmux send-keys -t $SESSION:camera \
  "source /opt/ros/humble/setup.bash && ros2 run v4l2_camera v4l2_camera_node --ros-args -p image_size:=\"[640,480]\"" C-m

sleep 3

echo "[2/9] 라이다 노드 시작..."
tmux new-window -t $SESSION -n lidar
tmux send-keys -t $SESSION:lidar \
  "cd ~/ydlidar_ros2_ws && source install/setup.bash && ros2 launch ydlidar_ros2_driver ydlidar_launch.py" C-m

sleep 5

echo "[3/9] slam_toolbox 시작 (실주행 SLAM, map->odom TF는 이제 slam_toolbox가 직접 발행)..."
tmux new-window -t $SESSION -n slam
tmux send-keys -t $SESSION:slam \
  "source /opt/ros/humble/setup.bash && ros2 launch slam_toolbox online_async_launch.py slam_params_file:=$(dirname "$0")/slam_toolbox_params.yaml use_sim_time:=False" C-m

sleep 2

echo "[4/9] odom->base_link TF 브로드캐스터 시작 (RPi5 /odom 구독, 실제 오도메트리)..."
tmux new-window -t $SESSION -n odomtf
tmux send-keys -t $SESSION:odomtf \
  "source /opt/ros/humble/setup.bash && source ~/ros2_ws/install/setup.bash && ros2 run petbot_odom_tf odom_tf_broadcaster" C-m

sleep 2

echo "[5/9] Nav2 bringup 시작 (slam_toolbox가 실제 /map을 발행하므로 기본 파라미터 사용, static_layer 포함)..."
tmux new-window -t $SESSION -n nav2
tmux send-keys -t $SESSION:nav2 \
  "source /opt/ros/humble/setup.bash && ros2 launch nav2_bringup navigation_launch.py use_sim_time:=False" C-m

sleep 8

echo "[6/9] person_locator 시작 (yolo-env, /person_location 상시 발행)..."
tmux new-window -t $SESSION -n locator
tmux send-keys -t $SESSION:locator \
  "source ~/yolo-env/bin/activate && source /opt/ros/humble/setup.bash && source ~/ros2_ws/install/setup.bash && python3 ~/ros2_ws/build/petbot_person_locator/petbot_person_locator/person_locator.py" C-m

sleep 3

echo "[7/9] wakeword_node 시작 (wakeword-env, ReSpeaker Lite 마이크, /wakeword_detected 발행)..."
tmux new-window -t $SESSION -n wakeword
tmux send-keys -t $SESSION:wakeword \
  "source ~/wakeword-env/bin/activate && source /opt/ros/humble/setup.bash && source ~/ros2_ws/install/setup.bash && python3 ~/ros2_ws/build/petbot_wakeword/petbot_wakeword/wakeword_node.py" C-m

sleep 3

echo "[8/9] owner_search 시작 (yolo-env, 웨이크워드 -> 회전탐색 -> 최근접 사람 접근)..."
tmux new-window -t $SESSION -n ownersearch
tmux send-keys -t $SESSION:ownersearch \
  "source ~/yolo-env/bin/activate && source /opt/ros/humble/setup.bash && source ~/ros2_ws/install/setup.bash && python3 ~/ros2_ws/build/petbot_owner_search/petbot_owner_search/owner_search_node.py" C-m

sleep 3

echo "[9/9] idle_wander 시작 (venv 불필요, 시스템 python3)..."
tmux new-window -t $SESSION -n wander
tmux send-keys -t $SESSION:wander \
  "source /opt/ros/humble/setup.bash && source ~/ros2_ws/install/setup.bash && python3 ~/ros2_ws/build/petbot_idle_behavior/petbot_idle_behavior/idle_wander.py" C-m

echo ""
echo "=========================================="
echo "9개 노드 전부 tmux 세션 'idle'에서 실행 중"
echo ""
echo "상태 확인:  tmux attach -t idle"
echo "창 전환:    Ctrl+B 누르고 손 떼고 숫자 0(camera) 1(lidar) 2(slam) 3(odomtf) 4(nav2) 5(locator) 6(wakeword) 7(ownersearch) 8(wander)"
echo "빠져나오기(계속 실행됨): Ctrl+B 누르고 손 떼고 D"
echo ""
echo "참고: owner_search와 idle_wander 둘 다 MoveInterface/cmd_vel을 건드릴 수 있어서,"
echo "웨이크워드가 idle_wander의 PATROL 중에 겹치면 두 노드가 동시에 이동 목표를 보낼 수 있음"
echo "(알려진 제한사항, 아직 조율 로직 없음)."
echo "=========================================="
