# rpicam-apps Docs

> **출처**: 라즈베리파이 공식 문서(`raspberrypi.com/documentation/computers/camera_software.html`)
>
> **버전 주의**: 옵션은 rpicam-apps 버전마다 다릅니다. 최종 확인은 항상 보드에서:
> ```bash
> rpicam-vid --help | less
> rpicam-still --help | less
> ```

**대상 환경**: Raspberry Pi OS Trixie / Pi Zero W (ARMv6) / OV5647 5MP

---

## 목차

1. [스택 개요](#1-스택-개요)
2. [앱 종류](#2-앱-종류)
3. [공통 옵션](#3-공통-옵션)
4. [화질 제어 옵션](#4-화질-제어-옵션)
5. [rpicam-still 전용](#5-rpicam-still-전용)
6. [rpicam-vid 전용](#6-rpicam-vid-전용)
7. [OV5647 센서 모드](#7-ov5647-센서-모드)
8. [스트리밍](#8-스트리밍)
9. [설정 파일](#9-설정-파일)
10. [Picamera2](#10-picamera2)
11. [Zero W 실전 레시피](#11-zero-w-실전-레시피)
12. [트러블슈팅](#12-트러블슈팅)

---

## 1. 스택 개요

라즈베리파이 카메라 소프트웨어는 세대별로 완전히 갈립니다.

| 세대 | OS | CLI | Python |
|---|---|---|---|
| 레거시 (MMAL) | Buster 이하 | `raspistill` / `raspivid` | `picamera` |
| libcamera | Bullseye | `libcamera-*` | `picamera2` |
| **libcamera (현행)** | **Bookworm / Trixie** | **`rpicam-*`** | **`picamera2`** |

Bookworm부터 레거시 스택은 **완전히 제거**되었습니다. `raspistill`을 쓰는 인터넷 예제는 Trixie에서 동작하지 않으며, `start_x=1`이나 `gpu_mem=128` 같은 레거시 설정도 더 이상 의미가 없습니다.

`rpicam-*`은 Bookworm에서 `libcamera-*`로부터 이름이 바뀐 것으로, 한동안 구 이름이 심볼릭 링크로 남아 있었습니다. 신규 코드는 `rpicam-` 사용을 권장합니다.

---

## 2. 앱 종류

| 명령 | 용도 |
|---|---|
| `rpicam-hello` | 카메라 동작 확인, 미리보기. 문제 진단의 출발점 |
| `rpicam-jpeg` | 단순 정지 촬영 (옵션 최소) |
| `rpicam-still` | 정지 촬영 풀 기능 (타임랩스, RAW, EXIF 등) |
| `rpicam-vid` | 영상 녹화 |
| `rpicam-raw` | 센서 원시 Bayer 데이터 저장 |
| `rpicam-detect` | 물체 감지 시 자동 촬영 (TFLite 필요, 기본 미포함인 경우 많음) |

### 최초 동작 확인

```bash
rpicam-hello --list-cameras   # 인식된 카메라와 지원 모드 전체 출력
rpicam-hello -t 2000 -n       # 2초간 구동 테스트 (미리보기 없이)
```

`--list-cameras` 출력은 이 문서 [7장](#7-ov5647-센서-모드)의 모드 표를 **실제 하드웨어 기준으로** 확인하는 가장 정확한 방법입니다.

---

## 3. 공통 옵션

모든 `rpicam-*` 앱에서 공통으로 쓰입니다.

### 기본

| 옵션 | 설명 |
|---|---|
| `-t, --timeout <ms>` | 실행 시간(밀리초). **`0`이면 무한** |
| `-o, --output <file>` | 출력 파일. `-`는 stdout, `udp://`/`tcp://`도 가능 |
| `-n, --nopreview` | 미리보기 끔. **SSH 헤드리스 환경에서는 사실상 필수** |
| `-v, --verbose <0-2>` | 로그 상세도 |
| `--config <file>` | 옵션을 파일에서 읽기 (긴 명령 관리에 유용) |
| `--list-cameras` | 카메라 및 지원 모드 목록 |
| `--camera <n>` | 카메라 여러 개일 때 선택 |

### 해상도와 센서 모드

| 옵션 | 설명 |
|---|---|
| `--width` / `--height` | **출력** 해상도 |
| `--mode <W:H:bitdepth:packing>` | **센서** 모드 강제 지정 |
| `--framerate <fps>` | 프레임레이트 |

> ⚠️ **`--width/--height`와 `--mode`는 다릅니다.**
> 전자는 최종 출력 크기, 후자는 센서가 실제로 읽어들이는 방식입니다. 센서 모드가 화각(FOV)을 결정하므로, 화각이 중요하다면 `--mode`를 반드시 명시하세요. 자세한 내용은 [7장](#7-ov5647-센서-모드).

### 방향과 크롭

| 옵션 | 설명 |
|---|---|
| `--hflip` / `--vflip` | 좌우 / 상하 반전 |
| `--rotation 0\|180` | 회전 (90/270은 미지원) |
| `--roi x,y,w,h` | 디지털 줌. 0~1 정규화 값. 예: `--roi 0.25,0.25,0.5,0.5` = 중앙 2배 줌 |

### 기타

| 옵션 | 설명 |
|---|---|
| `--flush` | 프레임마다 파일 flush. **전원 손실 대비에 유효** |
| `--post-process-file <json>` | 후처리 파이프라인 적용 |
| `--tuning-file <json>` | 센서 튜닝 파일 교체 (예: NoIR용) |

---

## 4. 화질 제어 옵션

### 기본 이미지 파라미터

| 옵션 | 범위 | 비고 |
|---|---|---|
| `--brightness` | -1.0 ~ 1.0 | 기본 0 |
| `--contrast` | 0 ~ | 기본 1.0 |
| `--saturation` | 0 ~ | 0이면 흑백 |
| `--sharpness` | 0 ~ | 기본 1.0 |
| `--ev` | -10 ~ 10 | 노출 보정(스톱 단위) |

### 노출

| 옵션 | 설명 |
|---|---|
| `--shutter <us>` | 셔터 속도 **고정**(마이크로초). 지정하면 자동 노출 해제 |
| `--gain <n>` | 아날로그 게인 고정 |
| `--exposure <mode>` | `normal` / `sport` / `long` |
| `--metering <mode>` | `centre` / `spot` / `average` / `custom` |

> 💡 **`--exposure sport`**: 자동 노출을 유지하면서 셔터를 짧게 편향시킵니다. 이동 중 촬영에서 모션 블러와 롤링셔터 왜곡을 줄이는 가장 간단한 방법입니다. 셔터를 완전히 고정(`--shutter`)하면 조도 변화에 대응하지 못하므로, 야외 산책처럼 밝기가 계속 변하는 상황에서는 `sport`가 정답입니다.

### 화이트밸런스

| 옵션 | 값 |
|---|---|
| `--awb <mode>` | `auto`, `incandescent`, `tungsten`, `fluorescent`, `indoor`, `daylight`, `cloudy`, `custom` |
| `--awbgains <r,b>` | 게인 직접 지정 (AWB 완전 고정) |

> 💡 **타임랩스에서는 AWB 고정이 중요합니다.** 자동으로 두면 프레임마다 색온도가 튀어 결과물이 깜빡거립니다(플리커). `--awb daylight` 또는 `--awbgains`로 고정하세요.

### 노이즈 제거

| 옵션 | 값 |
|---|---|
| `--denoise <mode>` | `auto`, `off`, `cdn_off`, `cdn_fast`, `cdn_hq` |

Zero W에서는 `cdn_fast`가 균형점입니다. `cdn_hq`는 CPU 여유가 없습니다.

### OV5647에서 쓸 수 없는 옵션

`--autofocus-mode`, `--autofocus-range`, `--lens-position` 등 오토포커스 관련 옵션은 **Camera Module 3 전용**입니다. OV5647은 렌즈를 손으로 돌려 조절하는 고정 초점 방식입니다.

---

## 5. rpicam-still 전용

| 옵션 | 설명 |
|---|---|
| `-e, --encoding` | `jpg`(기본), `png`, `bmp`, `rgb`, `yuv420` |
| `-q, --quality <0-100>` | JPEG 품질, 기본 93 |
| `-r, --raw` | DNG 형식 RAW 동시 저장 |
| `--thumb <w:h:q>` | 썸네일 설정. `none`이면 생략 |
| `--exif <tag=val>` | EXIF 태그 추가 |
| `--latest <link>` | 최신 파일을 가리키는 심볼릭 링크 생성 |
| `--immediate` | 미리보기 없이 즉시 촬영 |

### 타임랩스

| 옵션 | 설명 |
|---|---|
| `--timelapse <ms>` | 촬영 간격 |
| `--framestart <n>` | 파일 번호 시작값 |
| `--datetime` | 파일명을 촬영 일시로 자동 생성 |
| `--timestamp` | 파일명을 UNIX 타임스탬프로 생성 |

```bash
# 10초 간격 무한 타임랩스, 파일명 자동
rpicam-still -n -t 0 --timelapse 10000 --datetime \
  --awb daylight -o /home/piw/tl/
```

출력 경로에 `%04d` 같은 형식 지정자를 쓰면 번호가 매겨집니다:
```bash
-o /home/piw/tl/img_%04d.jpg
```

### 외부 트리거 촬영

| 옵션 | 설명 |
|---|---|
| `-k, --keypress` | Enter 입력 시 촬영 |
| `-s, --signal` | `SIGUSR1` 수신 시 촬영 |

```bash
rpicam-still -n -t 0 -s -o shot_%04d.jpg &
kill -SIGUSR1 <pid>   # 촬영 트리거
```

GPIO 버튼이나 외부 스크립트와 연동할 때 유용합니다.

---

## 6. rpicam-vid 전용

### 코덱과 비트레이트

| 옵션 | 설명 |
|---|---|
| `--codec` | `h264`(기본), `mjpeg`, `yuv420`, `libav` |
| `-b, --bitrate <bps>` | 비트레이트. 예: `3000000` = 3Mbps |
| `--profile` | `baseline` / `main` / `high` |
| `--level` | `4` / `4.1` / `4.2` |
| `--frames <n>` | 지정 프레임 수만큼 녹화 |

### 키프레임 — 후처리 성능에 직결

| 옵션 | 설명 |
|---|---|
| `--intra <n>` / `-g <n>` | 키프레임(I-frame) 간격, 프레임 단위 |
| `--inline` | **모든 키프레임에 SPS/PPS 헤더 삽입** |

> ⚠️ **`--inline`은 세그먼트 녹화와 스트리밍에서 필수입니다.** 없으면 두 번째 이후 세그먼트가 헤더를 갖지 못해 단독 디코딩이 불가능해집니다.
>
> 💡 **`--intra`는 나중에 프레임을 추출할 계획이라면 짧게 잡으세요.** 키프레임이 촘촘할수록 임의 위치 seek이 빨라집니다. 15fps에서 `--intra 15`면 1초마다 키프레임입니다.

### 파일 분할

| 옵션 | 설명 |
|---|---|
| `--segment <ms>` | 지정 시간마다 새 파일로 분할 |
| `--split` | 신호/키 입력 시점에 파일 분할 |
| `--circular <MB>` | 링 버퍼 녹화 (최근 N MB만 유지) |

```bash
# 5분 단위 분할 — 출력 파일명에 형식 지정자 필요
rpicam-vid -n -t 0 --segment 300000 --inline -o walk_%04d.h264
```

> 💡 **장시간 녹화에서 세그먼트 분할은 선택이 아니라 필수입니다.** 통짜 파일로 녹화하다 전원이 끊기면 전체를 잃지만, 5분 단위로 쪼개두면 마지막 조각만 손상됩니다.

### 녹화 제어

| 옵션 | 설명 |
|---|---|
| `-k, --keypress` | Enter로 녹화 일시정지/재개 |
| `-s, --signal` | `SIGUSR1`로 제어 |
| `--initial record\|pause` | 시작 상태 지정 |

### 출력 컨테이너

`.h264`는 컨테이너가 없는 **원시 스트림**이라 재생 시간·타임스탬프 정보가 없습니다. 세 가지 선택지가 있습니다.

**① 원시 h264 저장 후 PC에서 remux (Zero W 권장)**
```bash
# Pi에서
rpicam-vid ... -o out.h264
# PC에서 (재인코딩 없음, 순식간)
ffmpeg -fflags +genpts -r 15 -i out.h264 -c copy out.mp4
```

**② libav로 Pi에서 바로 MP4**
```bash
rpicam-vid --codec libav --libav-format mp4 -o out.mp4
```
편하지만 Zero W에서는 CPU 부담이 있습니다.

**③ MJPEG**
```bash
rpicam-vid --codec mjpeg -o out.mjpeg
```
용량이 매우 크지만 프레임 단위 손상에 강하고 디코딩이 단순합니다.

---

## 7. OV5647 센서 모드

**이 표가 OV5647 사용 시 가장 중요합니다.**

| 모드 | 화각(FOV) | 최대 fps | 비고 |
|---|---|---|---|
| 2592×1944 | **전체** | 15 | 풀 해상도 정지 촬영용 |
| 1920×1080 | **크롭 (약 2/3)** | 30 | ⚠️ 화각이 잘림 |
| **1296×972** | **전체** (2×2 비닝) | 42 | 영상 녹화 최적 |
| 1296×730 | 가로 전체 / 세로 크롭 | 49 | 16:9 |
| 640×480 | 전체 (비닝) | 60~90 | 고속 촬영 |

### 1080p 함정

무심코 `--width 1920 --height 1080`을 지정하면 센서가 **1920×1080 크롭 모드**를 선택해 화각이 약 2/3로 줄어듭니다. 풍경이나 주변 맥락을 담아야 하는 용도에서는 치명적입니다.

**전체 화각이 필요하면:**
```bash
--mode 1296:972 --width 1296 --height 972
```

비닝 모드는 화각 유지 외에도 저조도 노이즈가 유리하고, 처리해야 할 픽셀이 적어 Zero W CPU 부담도 훨씬 가볍습니다. 4:3 비율이라 시네마틱하지는 않지만, 정보량 기준으로는 1080p 크롭보다 낫습니다.

### 실제 하드웨어 확인

```bash
rpicam-hello --list-cameras
```
이 출력이 최종 근거입니다.

---

## 8. 스트리밍

### UDP

```bash
# 송신 (Pi)
rpicam-vid -n -t 0 --inline -o udp://192.168.0.10:5000
# 수신 (PC)
ffplay -fflags nobuffer -flags low_delay udp://0.0.0.0:5000
```

### TCP

```bash
# 송신 (Pi, 접속 대기)
rpicam-vid -n -t 0 --inline --listen -o tcp://0.0.0.0:8888
# 수신 (PC)
ffplay tcp://<pi-ip>:8888
```

### 파이프

```bash
rpicam-vid -n -t 0 --codec yuv420 -o - | your_program
```

> ⚠️ **Zero W 스트리밍 현실**: 2.4GHz 802.11n이라 실측 대역폭이 2~4 MB/s 수준입니다. 720p 이하 저비트레이트로 낮추고, `--inline`을 반드시 붙이세요(수신 측이 중간부터 붙어도 디코딩 가능).

---

## 9. 설정 파일

**경로: `/boot/firmware/config.txt`** (Bookworm 이후. 구 `/boot/config.txt` 아님)

```ini
# 자동 감지 (기본, 대부분 이걸로 충분)
camera_auto_detect=1

# 자동 감지 실패 시 명시적 지정
# camera_auto_detect=0
# dtoverlay=ov5647
```

### 관련 설정

```ini
# RTC 모듈 (Zero W는 RTC 없음 — 시각 정확도가 중요하면 권장)
dtoverlay=i2c-rtc,ds3231

# GPIO 안전 종료 버튼 (GPIO3 = 물리 5번핀, GND = 6번핀)
dtoverlay=gpio-shutdown

# USB 가젯 모드 (PC와 USB 케이블로 네트워크 연결)
dtoverlay=dwc2
```
> USB 가젯은 `/boot/firmware/cmdline.txt`의 `rootwait` 뒤에 `modules-load=dwc2,g_ether`도 추가해야 합니다(파일 전체가 한 줄이어야 함).

### 레거시 설정은 무시하세요

`start_x=1`, `gpu_mem=128`은 libcamera 스택에서 **아무 효과가 없습니다.** 오래된 튜토리얼에 자주 등장하지만 넣을 필요 없습니다.

---

## 10. Picamera2

CLI로 부족할 때 쓰는 Python 라이브러리입니다.

### 설치

```bash
sudo apt install -y python3-picamera2
```

> ⚠️ **pip로 설치하지 마세요.** libcamera 바인딩은 시스템 패키지로만 제공됩니다. 가상환경이 필요하면:
> ```bash
> python3 -m venv --system-site-packages venv
> ```

### 기본 사용

```python
from picamera2 import Picamera2
from picamera2.encoders import H264Encoder
from picamera2.outputs import FileOutput
import time

picam2 = Picamera2()
config = picam2.create_video_configuration(
    main={"size": (1296, 972)},
    controls={"FrameRate": 15}
)
picam2.configure(config)

picam2.start_recording(H264Encoder(bitrate=3_000_000), FileOutput("out.h264"))
time.sleep(10)
picam2.stop_recording()
```

### CLI 대신 Picamera2를 써야 하는 경우

- **듀얼 스트림**이 필요할 때 (예: 고해상도 녹화 + 저해상도 분석용 동시 출력)
- 프레임 데이터를 NumPy 배열로 직접 처리해야 할 때
- 촬영 조건을 프로그램 로직으로 동적 제어해야 할 때

`rpicam-vid`와 `rpicam-still`은 **동시 실행할 수 없습니다**(카메라는 배타적 자원). 영상과 정지 이미지를 동시에 뽑아야 하면 Picamera2의 `main` + `lores` 듀얼 스트림이 유일한 방법입니다.

---

## 11. Zero W 실전 레시피

### 10초 동작 테스트

```bash
rpicam-vid -n -t 10000 -o test.h264
ls -lh test.h264
ffprobe test.h264
```

### 이동 중 장시간 녹화 (산책 등)

```bash
rpicam-vid -n -t 0 \
  --mode 1296:972 --width 1296 --height 972 \
  --framerate 15 \
  --codec h264 --bitrate 3000000 \
  --intra 15 --inline --flush \
  --exposure sport --denoise cdn_fast \
  --segment 300000 \
  -o "/home/piw/walk/$(date +%Y%m%d_%H%M%S)_%04d.h264"
```

각 옵션의 근거:

| 옵션 | 이유 |
|---|---|
| `--mode 1296:972` | 전체 화각 확보 (1080p는 크롭됨) |
| `--framerate 15` | Zero W CPU 여유 확보. 대부분 용도에 충분 |
| `--intra 15 --inline` | 1초 키프레임 + 세그먼트 독립 디코딩 |
| `--exposure sport` | 보행 중 모션 블러 억제 |
| `--segment 300000` | 5분 분할 — 전원 손실 시 피해 최소화 |
| `--flush` | 디스크 기록 지연 최소화 |

### 용량 계산

| 설정 | 시간당 |
|---|---|
| 1296×972 @10fps, 2Mbps | 0.9 GB |
| 1296×972 @15fps, 3Mbps | 1.35 GB |
| 1920×1080 @15fps, 4Mbps | 1.8 GB |
| 640×480 @15fps, 1Mbps | 0.45 GB |

계산식: `비트레이트(Mbps) ÷ 8 × 3600 = 시간당 MB`

### 타임랩스는 영상에서 추출하는 편이 낫습니다

`rpicam-vid`와 `rpicam-still`은 동시 실행이 안 되므로, 녹화 영상에서 프레임을 뽑아 타임랩스를 만드는 쪽이 단순합니다.

```bash
# PC에서: 30초마다 1프레임 → 24fps 타임랩스
ffmpeg -i walk.mp4 -vf "fps=1/30" -c:v libx264 -r 24 timelapse.mp4
```

Pi 쪽은 녹화 하나만 신경 쓰면 되고, 실패 지점이 줄어듭니다.

### 부팅 자동 녹화 (systemd)

`/etc/systemd/system/walkcam.service`:

```ini
[Unit]
Description=Walk Camera Recording
After=multi-user.target

[Service]
Type=simple
User=piw
ExecStart=/home/piw/walkcam.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now walkcam.service
journalctl -u walkcam.service -f    # 로그 확인
```

### 전력 관리

```bash
sudo rfkill block wifi      # 야외 녹화 시 WiFi 차단 (전력 절감)
sudo rfkill unblock wifi    # 복귀 후 해제
vcgencmd get_throttled      # 0x0 이면 정상
```

- 녹화 중 소비전류: 약 250~350mA @5V
- 5000mAh 보조배터리 기준 10시간 이상
- ⚠️ 일부 보조배터리는 저전류에서 자동 차단됩니다. 실사용 전 1시간 연속 테스트 필수

### 시계 문제

**Zero W에는 RTC가 없습니다.** 네트워크 없이 부팅하면 시각이 부정확해지고, 파일명·EXIF의 타임스탬프가 전부 어긋납니다.

- **임시 대응**: 집에서 WiFi 연결 상태로 부팅해 NTP 동기화 → 재부팅 없이 사용
- **정공법**: DS3231 I2C RTC 모듈 추가 (`dtoverlay=i2c-rtc,ds3231`)

---

## 12. 트러블슈팅

### 카메라가 인식되지 않음

```bash
rpicam-hello --list-cameras
dmesg | grep -i -E "ov5647|camera|csi"
vcgencmd get_camera        # 참고용 (libcamera 스택에서는 신뢰도 낮음)
```

점검 순서:
1. **리본 케이블** — Zero W는 일반 Pi보다 좁은 **22핀 미니 CSI 케이블**을 사용합니다. 일반 15핀은 물리적으로 안 맞습니다
2. **방향** — 금속 접점 면이 올바른 쪽을 향해야 합니다
3. **체결** — 커넥터 래치가 완전히 눌렸는지
4. **전원** — 부족하면 카메라 초기화가 실패합니다
5. `/boot/firmware/config.txt`의 `camera_auto_detect=1` 확인

### 프레임 드랍

```bash
vcgencmd measure_temp
vcgencmd get_throttled
top -b -n 1 | head -20
```

대응 순서: 프레임레이트 ↓ → 비트레이트 ↓ → 해상도 ↓ → `--denoise cdn_off`

### 영상이 재생되지 않음

원시 `.h264`는 대부분의 플레이어에서 제대로 재생되지 않습니다. 정상 동작입니다.
```bash
ffmpeg -fflags +genpts -r 15 -i out.h264 -c copy out.mp4
```

### 화각이 좁게 나옴

센서 크롭 모드가 선택된 것입니다. `--mode 1296:972`를 명시하세요. [7장](#7-ov5647-센서-모드) 참조.

### 영상이 어둡거나 흔들림

- 어두움: `--ev 0.5` ~ `--ev 1.0`
- 흔들림/블러: `--exposure sport`
- 색감 이상: `--awb daylight` 등으로 고정

### Python에서 `ModuleNotFoundError: picamera2`

pip 가상환경 문제입니다. `sudo apt install python3-picamera2` 후 시스템 Python을 쓰거나, `python3 -m venv --system-site-packages`로 환경을 다시 만드세요.

---

## 참고 링크

| 문서 | URL |
|---|---|
| 카메라 소프트웨어 공식 문서 | `raspberrypi.com/documentation/computers/camera_software.html` |
| Picamera2 매뉴얼 (PDF) | `datasheets.raspberrypi.com/camera/picamera2-manual.pdf` |
| rpicam-apps 소스 | `github.com/raspberrypi/rpicam-apps` |
| Picamera2 저장소 | `github.com/raspberrypi/picamera2` |
| 라즈베리파이 공식 포럼 | `forums.raspberrypi.com` |

**가장 신뢰할 수 있는 정보원은 보드 자체입니다:**
```bash
rpicam-vid --help
rpicam-still --help
rpicam-hello --list-cameras
```