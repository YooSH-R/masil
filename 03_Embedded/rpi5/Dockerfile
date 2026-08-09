FROM ros:humble

ENV DEBIAN_FRONTEND=noninteractive

# 라즈베리파이 5에 RTC 배터리가 없어서 부팅 직후엔 시계가 실제 시각보다
# 뒤쳐져 있을 수 있음 -> apt가 리포지토리 Release 파일을 "아직 유효하지
# 않음"으로 오판하는 걸 방지하기 위해 유효기간 체크를 건너뜀
RUN printf 'Acquire::Check-Valid-Until "false";\nAcquire::Check-Date "false";\n' > /etc/apt/apt.conf.d/10no-check-valid-until

# 라즈베리파이 5 필수 하드웨어 제어 및 디버깅 패키지 설치
RUN apt-get update && apt-get install -y \
    python3-gpiozero \
    python3-lgpio \
    libgpiod-dev \
    gpiod \
    i2c-tools \
    libi2c-dev \
    build-essential \
    python3-pip \
    nano \
    vim \
    net-tools \
    iputils-ping \
    ros-humble-robot-localization \
    && rm -rf /var/lib/apt/lists/*

# BNO055 IMU (adafruit_bno055 + board/busio 지원용 blinka)
RUN pip3 install --no-cache-dir adafruit-circuitpython-bno055 adafruit-blinka

WORKDIR /root/ros2_ws

# 터미널 접속 시 ROS2 및 빌드 환경 자동 로드
RUN echo "source /opt/ros/humble/setup.bash" >> /root/.bashrc && \
    echo "if [ -f /root/ros2_ws/install/setup.bash ]; then source /root/ros2_ws/install/setup.bash; fi" >> /root/.bashrc

CMD ["/bin/bash"]