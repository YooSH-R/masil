## 시간 동기화

**시간 동기화 후 모든 컨테이너 및 노드 재실행**

### 파이5 세팅

```bash
sudo date -s "2026-08-09 11:30:00"    # 실제 현재 시각으로
chronyc tracking
```

### 젯슨 세팅

```bash
sudo chronyc makestep     # 큰 오차를 즉시 점프 보정
date 
```


## 맵 그리기 (SLAM 세팅)

### lidar 실행
```bash
cd $HOME/ros_ws && ./run.sh
```

### lidar 실행 (build)
```bash
cd $HOME/ros_ws && ./run.sh build
```

### 키보드 명령 노드 실행

```bash
ros2 run jetson_teleop keyboard_node
```

### slam_toolbox 초기화 및 실행

```bash
ros2 launch slam_toolbox \
  online_async_launch.py \
  slam_params_file:=$HOME/ros_ws/src/jetson_navigation/config/mapper_params_x4pro.yaml
```

### slam_toolbox 초기화 (재실행 전 작업)

```bash
pkill -f slam_toolbox && sleep 2
```

### 맵 저장

```bash
sudo apt install ros-humble-nav2-map-server -y    # 최초 1회 (설치)
ros2 run nav2_map_server map_saver_cli -f $HOME/ros_ws/src/jetson_navigation/maps/ver3/map
```

### 맵 이미지 생성 (생성된 .pgm을 .png로 시각화)

```bash
sudo apt install imagemagick -y    # 최초 1회 시행 (설치)
convert $HOME/ros_ws/src/jetson_navigation/maps/ver4/map.pgm \
  $HOME/ros_ws/src/jetson_navigation/maps/ver4/map.png
```


## nav2 세팅

### localization + navigation

```bash
ros2 launch nav2_bringup bringup_launch.py \
  map:=$HOME/ros_ws/src/jetson_navigation/maps/ver4/map.yaml \
  params_file:=$HOME/ros_ws/src/jetson_navigation/config/nav2_params.yaml \
  use_sim_time:=false
```

### 맵 rviz2에 다시 불러오기

```bash
ros2 service call /map_server/load_map nav2_msgs/srv/LoadMap "{map_url: '/home/jetson/ros_ws/src/jetson_navigation/maps/ver3/map.yaml'}"
```

# scenario

```bash
source ~/scripts/start_idle_wander2.sh
source ~/scripts/tirgger_demo_square_path.sh
source ~/scripts/stop_idle_wander2.sh
```