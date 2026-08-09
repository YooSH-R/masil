# RPi5 (Body)

로봇의 저수준 제어(모터 구동, 오도메트리)를 담당하는 Raspberry Pi 5 쪽 ROS2 워크스페이스입니다. Jetson과는 이더넷 케이블 직결 + 표준 ROS2(DDS) 토픽으로 통신합니다 (커스텀 UART 프로토콜 아님).

## 하드웨어

- **모터 드라이버**: Cytron MDD3A, 직접 GPIO PWM 제어 (I2C 아님)
  - 왼쪽: GPIO6(forward)/GPIO5(backward) — MDD3A M1 채널
  - 오른쪽: GPIO17(forward)/GPIO27(backward) — MDD3A M2 채널
  - 모터 채널 번호(M1/M2)와 실제 좌우가 반대라서 위처럼 매핑됨 (`motor_control_node.py` 주석 참고)
- **엔코더**: 2채널 홀센서, 감속기어 내장 (IG-32GM+Encoder)
  - 왼쪽: GPIO26(A)/GPIO21(B), 오른쪽: GPIO20(A)/GPIO16(B)
  - 왼쪽 엔코더는 오른쪽과 부호가 반대라 코드에서 반전 처리됨
- **IMU**: BNO055 (I2C, 주소 0x28)
- 바퀴 지름 65mm(반지름 0.0325m), 바퀴 간격 230mm — 실측값 (캘리퍼스/줄자)

## 소프트웨어 구조

ROS2 Humble, Docker 컨테이너(`ros:humble` 베이스 + 커스텀 Dockerfile)에서 개발/실행합니다. 호스트에 ROS2 네이티브 설치 없음.

```
cmd_vel (geometry_msgs/Twist, Jetson 발행)
  └─▶ motor_control_node (MDD3A 구동 + 엔코더 읽기)
        └─▶ /wheel_odom (nav_msgs/Odometry, 엔코더 기반 원시 오도메트리)
                              ┐
imu_node (BNO055) ─▶ /imu/data (sensor_msgs/Imu)  ┴─▶ ekf_node (robot_localization)
                                                          └─▶ /odom (Jetson이 구독하는 최종 토픽)
```

- `motor_control_node`: `/cmd_vel` 구독, differential drive kinematics로 좌우 바퀴 속도 계산, MDD3A PWM 구동, 엔코더 적분해서 `/wheel_odom` 발행. 300ms 동안 cmd_vel이 안 오면 자동 정지(워치독).
- `imu_node`: BNO055에서 orientation/각속도 읽어서 `/imu/data` 발행.
- `ekf_node` (robot_localization 패키지): `/wheel_odom`(속도만 신뢰) + `/imu/data`(yaw만 신뢰) 융합 → `/odom` 발행. 설정: `ros2_ws/src/encoder_pkg/config/ekf.yaml`.

모든 파라미터(바퀴 크기, 엔코더 틱/회전, 최대속도, 워치독 시간 등)는 실측 캘리브레이션된 값이 기본값으로 들어가 있습니다 (`motor_control_node.py` 상단 `declare_parameter` 참고).

## 빌드 & 실행

```bash
# 컨테이너 기동 (최초 1회, 이후엔 restart:unless-stopped로 재부팅시 자동 기동)
cd rpi5 && docker compose up -d
docker exec -it rpi5_humble bash

# 컨테이너 안에서
cd ~/ros2_ws && colcon build --packages-select encoder_pkg
source install/setup.bash

# 세 노드 실행 (각각 별도 터미널/백그라운드)
ros2 run encoder_pkg motor_control_node
ros2 run encoder_pkg imu_node
ros2 run robot_localization ekf_node --ros-args --params-file ~/ros2_ws/src/encoder_pkg/config/ekf.yaml -r odometry/filtered:=odom
```

`ROS_DOMAIN_ID=30`으로 고정되어 있습니다 (Jetson과 동일해야 함). 컨테이너는 `network_mode: host` + `privileged: true`라 I2C/GPIO 디바이스에 별도 매핑 없이 접근됩니다.

⚠️ 세 노드를 자동 기동시키는 launch 파일은 아직 없습니다 — 컨테이너/노드가 재시작되면 수동으로 다시 실행해야 합니다 (TODO).

## 실측 검증

로봇을 바닥에 내려놓고 `/cmd_vel`로 0.15m/s 직진 3초 명령 후 실제 이동거리(줄자 ~14cm)와 `/odom` 값(14.15cm)이 거의 정확히 일치함을 확인했습니다.
