#!/bin/bash
# stop_person_approach.sh
SESSION="approach"

echo "tmux 세션 '$SESSION' 안의 노드들을 종료합니다..."

for win in camera lidar statictf nav2 approach; do
  tmux send-keys -t $SESSION:$win C-c 2>/dev/null || true
done

sleep 2

tmux kill-session -t $SESSION 2>/dev/null || true

pkill -9 -f v4l2_camera_node 2>/dev/null || true
pkill -9 -f ydlidar_ros2_driver_node 2>/dev/null || true
pkill -9 -f static_transform_publisher 2>/dev/null || true
pkill -9 -f nav2 2>/dev/null || true
pkill -9 -f person_approach 2>/dev/null || true

sleep 1

echo "정리 완료. 남은 노드 확인:"
ros2 node list 2>/dev/null || echo "(노드 없음 또는 확인 불가)"
