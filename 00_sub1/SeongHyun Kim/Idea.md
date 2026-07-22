# AIoT 기반 긴급탈출 도우미 RC카

## 1. 프로젝트 개요

- **주제 분야**: AIoT (AI + IoT), Physical AI, 엣지 컴퓨팅
- **한 줄 정의**: 화재, 터널 붕괴 등 인명 피해 위험이 있는 재난 현장에서 가스/유해환경을 실시간으로 탐지하고, 위험 구역을 회피하는 **최적 대피 경로를 스스로 찾아 안내·주행하는 RC카**
- **메인 하드웨어**: NVIDIA Jetson Orin Nano + Raspberry Pi 5 (듀얼 보드 구성)

## 2. 배경 및 문제의식

- 화재/터널 붕괴 같은 재난 현장은 연기, 유해가스, 붕괴물로 인해 **사람이 직접 진입해 상황을 파악하기 위험**하고, 특히 터널처럼 밀폐된 공간은 화재 확산이 빠르고 GPS 신호도 잡히지 않아 기존 위치 기반 대피 유도가 어렵다.
- 실제로 국내외에서 정찰 로봇(사족보행 로봇개, 바퀴형 로봇)에 라이다·이중 스펙트럼 카메라·가스 감지 모듈을 탑재해 화재 현장을 먼저 탐색하고 유해가스를 감지하는 사례가 늘고 있다. 국내 소방청도 유해가스 방출 시 사람보다 로봇이 먼저 탐지·수색하는 테스트베드를 개발한 바 있다.
- 기존 터널/건물의 대피 유도 방식은 대부분 **고정된 유도등·표지판**(화재 지점 쪽 적색, 반대쪽 녹색 점등 등) 방식이라 실시간 상황 변화(연기 확산 방향, 붕괴 위치 변화)에 유연하게 대응하기 어렵다. 이를 보완하기 위해 IoT 센서(가스, 온도, 연기)와 실시간 경로 재계산 알고리즘을 결합한 "동적 대피 경로 안내" 연구가 활발히 진행 중이다.
- → **본 프로젝트의 차별점**: 고정 설비가 아닌 **이동형 RC카**가 현장에 직접 진입해 실시간으로 위험을 감지하고, 스스로(혹은 요구조자를 유도하며) 안전한 경로로 탈출하는 것을 목표로 한다.

## 3. 핵심 아이디어

1. RC카가 재난 현장(화재/터널 등)에 투입되어 주행하며 주변 환경 데이터를 실시간 수집
2. 탑재된 가스 센서로 CO, 가연성 가스(LPG/메탄 등), 연기 등 유해 물질 농도를 측정
3. 카메라(Jetson Orin Nano의 엣지 AI 추론)로 화염, 연기, 장애물, 붕괴물을 시각적으로 인식
4. 가스 농도 + 시각 정보 + 초음파/거리 센서 데이터를 종합해 **위험도 맵을 실시간 갱신**
5. 위험 구역을 회피하는 최단/최안전 경로를 재탐색(A*, 인공 포텐셜 필드, 동적 경로 재계산 등)하여 자율 주행 또는 대피자 유도
6. 위험 상황 및 경로 정보를 서버/관제 화면(IoT 대시보드)으로 실시간 전송해 구조대가 상황을 파악 가능하게 함

## 4. 하드웨어 구성 및 역할 분담

실제 상용 ROS2 듀얼보드 로봇(Hiwonder JetRover/ROSOrin, Yahboom ROSMASTER X3 등)의 구성 방식을 참고하여 아래와 같이 역할을 분담한다.

| 보드 | 역할 |
|---|---|
| **Jetson Orin Nano** (최대 67 TOPS, Ampere GPU) | 카메라 영상 기반 **화염/연기/장애물 객체 탐지**(YOLO11/YOLOv26 등 엣지 최적화 모델), 위험도 판단, 경로 재계산 등 GPU 연산이 필요한 AI 워크로드 담당 |
| **Raspberry Pi 5** (Cortex-A76 쿼드코어 2.4GHz) | 가스 센서(MQ-2, MQ-7 등) 데이터 수집, 초음파/거리 센서 인터페이스, 모터·서보 구동 제어, Wi-Fi/BT 통신으로 관제 서버와 실시간 데이터 송수신 |
| **통신** | 두 보드 간 ROS2(DDS) 또는 UART/시리얼 연결로 센서·판단 데이터 공유 |

### 주요 센서/부품 후보
- **가스 센서**: MQ-2(가연성 가스, 연기, LPG), MQ-7(일산화탄소) — Raspberry Pi는 ADC가 없으므로 MCP3002 등 외부 ADC 필요
- **비전 센서**: RGB 카메라 (필요 시 열화상 카메라 추가 검토 — 연기 속 시야 확보)
- **거리/장애물 센서**: 초음파 센서 또는 라이다(예산에 따라 선택)
- **구동부**: RC카 섀시 + 모터 드라이버 + 서보(조향)

## 5. 주요 기능 (MVP 우선순위 제안)

1. **가스/위험 감지**: 가스 센서로 위험 수치 임계값 초과 시 해당 구역을 "위험"으로 표시
2. **실시간 장애물/화염 인식**: Jetson에서 카메라 스트림을 YOLO 계열 모델로 추론하여 화염, 연기, 낙하물 등 인식
3. **동적 경로 탐색 및 회피 주행**: 위험 구역을 반영해 경로를 실시간 재계산(A* 기반 + 위험도 가중치)하며 자율주행
4. **원격 모니터링/관제**: 센서값·카메라 영상·현재 위치 및 경로를 실시간으로 대시보드에 전송 (구조대 지원용)
5. (확장) **대피자 유도**: LED/음성/디스플레이로 사람에게 안전한 방향 안내
6. (확장) **다중 로봇 간 정보 공유(V2X류 통신)**: 여러 RC카가 각자 탐지한 위험 정보를 공유해 맵을 함께 구축

## 6. 참고할 만한 기존 프로젝트/기술

- **DEEP Robotics 소방 정찰 로봇**: 라이다 + 이중 스펙트럼 PTZ 카메라 + 가스 감지 모듈로 화재 현장 탐색 및 유해가스 감지
- **국내 소방청 로봇 테스트베드**: 유해가스 방출 시 로봇이 사람보다 먼저 탐지·수색
- **터널 화재 대피 유도 특허(배재대)**: 워터커튼 + 유도등 방식의 고정형 대피 유도 시스템 — 본 프로젝트는 이를 "이동형"으로 확장하는 개념
- **IoT 기반 스마트 터널 사고 경보 시스템**: 불꽃/가스/충격 감지 센서 → 임계값 초과 시 경보 및 Wi-Fi로 안내 메시지 전송
- **동적 화재 대피 경로 알고리즘 연구**: 그래프 이론 + 가스/온도/연기 센서를 결합한 실시간 경로 재계산, A*·개미 군집 알고리즘(ACO) 등을 활용해 화재 확산을 반영한 최적 탈출 경로 도출 — 본 프로젝트의 경로 탐색 알고리즘 설계에 직접 참고 가능
- **JetRacer / Donkey Car / JetCar**: Jetson·Raspberry Pi 기반 자율주행 RC카의 기본 아키텍처(카메라 기반 주행, 딥러닝 조향) 참고
- **Hiwonder JetRover / ROSOrin**: Jetson + Raspberry Pi 5 듀얼보드로 매핑·내비게이션·추적/회피를 구현한 상용 ROS2 로봇 — 하드웨어 아키텍처 참고용

## 7. 기대 효과

- 사람이 직접 진입하기 위험한 재난 초기 현장에서 **선제적으로 위험을 탐지**하여 인명 피해를 줄일 수 있음
- 고정형 유도 설비 대비 **현장 투입이 유연**하고, 실시간으로 변화하는 위험 상황에 맞춰 경로를 동적으로 갱신 가능
- 엣지 AI(Jetson)를 활용해 통신이 불안정한 지하/터널 환경에서도 **로컬에서 즉시 판단**이 가능 (클라우드 의존도 최소화)

## 8. 추후 검토 필요 사항

- 연기가 자욱한 환경에서 RGB 카메라만으로 충분한 인식이 가능한지 → 열화상 카메라 병행 필요성 검토
- 가스 센서(MQ 시리즈)의 응답 속도 및 정확도가 실제 위험 판단에 충분한지 검증
- 실내(GPS 불가) 환경에서의 위치 추정 방식 (SLAM, UWB, 오도메트리 등) 결정 필요
- 실제 재난 상황을 모사한 테스트 환경(연기/장애물 트랙) 구성 방안

---

### 참고 자료 (Sources)
- [中 화재 현장에 '로봇 소방대' 뜬다 - ZDNet Korea](https://zdnet.co.kr/view/?no=20260120133003)
- [화재 현장 불 끄고 가스 탐지하는 소방 로봇 - ZDNet Korea](https://zdnet.co.kr/view/?no=20220510154437)
- [Emergency Rescue - DEEP Robotics](https://www.deeprobotics.us/industry/emergency-rescue/)
- [Smart Disaster Response in Vehicular Tunnels (MDPI)](https://www.mdpi.com/2071-1050/10/7/2509)
- [Robot-aided human evacuation optimal path planning for fire drill in buildings (ScienceDirect)](https://www.sciencedirect.com/science/article/abs/pii/S2352710223006915)
- [A Rescue-Assistance Navigation Method by Using the Underground Location of WSN after Disasters (PMC)](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7218744/)
- [Time-Aware and Temperature-Aware Fire Evacuation Path Algorithm in IoT-Enabled Multi-Story Multi-Exit Buildings (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC7795275/)
- [Design of Intelligent Firefighting and Smart Escape Route Planning System Based on Improved Ant Colony Algorithm (PMC)](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11479322/)
- [Fire emergency management of large shopping malls: IoT-based evacuee tracking and dynamic path optimization (ScienceDirect)](https://www.sciencedirect.com/science/article/pii/S1110016824010068)
- [배재대 철도건설공학과, 터널 화재 대피 시스템 특허 출원 - 사이언스타임즈](https://www.sciencetimes.co.kr/nscvrg/view/menu/248?searchCategory=220&nscvrgSn=261399)
- [사물 인터넷 기반 스마트 터널 사고 경보 시스템](https://www.kci.go.kr/kciportal/ci/sereArticleSearch/ciSereArtiView.kci?sereArticleSearchBean.artiId=ART003115219)
- [KR20060103727A - 화재시 최단거리 출구를 안내하는 비상 유도등 시스템 - Google Patents](https://patents.google.com/patent/KR20060103727A/ko)
- [Lesson 04: Gas Sensor Module (MQ-2) - SunFounder Docs](https://docs.sunfounder.com/projects/umsk/en/latest/05_raspberry_pi/pi_lesson04_mq2.html)
- [GitHub - tutRPi/Raspberry-Pi-Gas-Sensor-MQ](https://github.com/tutRPi/Raspberry-Pi-Gas-Sensor-MQ)
- [Jetson Orin Nano Super Developer Kit - NVIDIA](https://www.nvidia.com/en-us/autonomous-machines/embedded-systems/jetson-orin/nano-super-developer-kit/)
- [Raspberry Pi 5 Product Brief (PDF)](https://datasheets.raspberrypi.com/rpi5/raspberry-pi-5-product-brief.pdf)
- [YOLO11 on Jetson Orin Nano: Benchmarks & Performance - Ultralytics](https://www.ultralytics.com/blog/ultralytics-yolo11-on-nvidia-jetson-orin-nano-super-fast-and-efficient)
- [Hiwonder JetRover](https://www.hiwonder.com/products/jetrover)
- [Hiwonder ROSOrin](https://www.hiwonder.com/products/rosorin)
- [JetRacer (NVIDIA-AI-IOT, GitHub)](https://github.com/NVIDIA-AI-IOT/jetracer)
