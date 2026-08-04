FROM ros:humble

ENV DEBIAN_FRONTEND=noninteractive

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