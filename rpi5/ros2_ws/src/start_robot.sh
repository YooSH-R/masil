#!/bin/bash
# Auto-start entrypoint for the rpi5_humble container (invoked as the
# container's main command via docker-compose). Builds encoder_pkg if it
# hasn't been built yet in this container instance (fresh/rebuilt containers
# lose ~/ros2_ws/install, but ros2_ws/src survives via the volume mount),
# then launches the full robot bringup and stays in the foreground so
# `restart: unless-stopped` actually restarts this if it dies.
set -e

source /opt/ros/humble/setup.bash
cd /root/ros2_ws
colcon build --packages-select encoder_pkg
source install/setup.bash

exec ros2 launch encoder_pkg bringup.launch.py
