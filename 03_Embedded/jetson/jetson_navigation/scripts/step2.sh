#!/bin/bash
# 터미널 2: AI 백그라운드 노드
source /opt/ros/humble/setup.bash
source ~/ros_ws/install/setup.bash

echo "======== [2/3] Wakeword & IdleWander 노드 런칭 ========"
ros2 run petbot_wakeword wakeword_node &
sleep 2
ros2 run petbot_idle_behavior idle_wander2