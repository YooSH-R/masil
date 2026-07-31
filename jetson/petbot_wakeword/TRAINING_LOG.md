# "마실아" 웨이크워드 학습 기록

날짜: 2026-07-29 ~ 2026-07-30
목표: "마실아"라고 부르면 로봇이 인식하는 커스텀 웨이크워드 모델 제작 (S15P11A203-248)

---

## 1. 배경 및 방식 결정

### 1차 시도: Picovoice Porcupine — 실패
- 무료 계정 가입 시 "commercial use case" 승인 대기 상태에 걸려서 AccessKey를 못 받음
- 승인 시점을 알 수 없어 데모 일정상 포기

### 2차 시도: openWakeWord — 최종 채택
- 완전 오픈소스, 계정/API 키 불필요, 오프라인 학습 가능
- 단점: 한국어 지원 약함 → 직접 학습 필요
- 한국어 Piper TTS 보이스(`ko_KR-kss-medium`)가 **싱글 스피커**라 목소리 다양성이 부족한 게 핵심 리스크였음
  → 완화책: TTS 합성 + 실제 사람 목소리 녹음(팀원 포함, 총 67개)을 함께 학습 데이터로 사용

---

## 2. 환경 구축

- **`~/yolo-env`(기존 YOLO/CUDA 환경)와 완전히 분리된 `~/wakeword-env` venv를 새로 생성**
  - 이유: 처음에 yolo-env에 openWakeWord 관련 패키지를 설치하다가 `numpy` 2.x로 강제 업그레이드되면서 Jetson 전용 PyTorch(CUDA 빌드)가 일반 PyPI torch로 덮어써짐 → **CUDA가 완전히 죽는 사고 발생**
  - NVIDIA 공식 wheel(`torch-2.5.0a0+872d972e41.nv24.08`)을 재다운로드해서 복구했고, 이후로는 절대 yolo-env를 건드리지 않기로 함

---

## 3. 겪은 문제와 해결 (시간순)

| # | 문제 | 원인 | 해결 |
|---|---|---|---|
| 1 | `pvporcupine` import 시 `NotImplementedError: Unsupported CPU: '0xd42'` | Jetson Orin의 Cortex-A78AE 코어를 Picovoice가 공식 지원 안 함 | `_util.py`에 0xd42 → cortex-a76 바이너리 재사용하도록 로컬 패치 (결국 Porcupine 자체를 안 쓰게 되면서 무의미해졌지만 기록으로 남김) |
| 2 | pip이 yolo-env의 `numpy`를 2.x로, `torch`를 일반 PyPI 버전으로 덮어씀 | `piper-sample-generator` 설치 시 의존성 해결 과정에서 발생 | **원인 발견 즉시 작업 중단**, NVIDIA 공식 wheel 재다운로드로 복구, 이후 학습 전용 venv(`wakeword-env`)로 완전 분리 |
| 3 | `ModuleNotFoundError: No module named 'piper_train'` | `piper-sample-generator`가 구버전 Piper 학습 코드(`piper_train.vits.commons`)를 참조하는데 최신 Piper는 `piper.train`으로 이름이 바뀌어 존재하지 않음 (업스트림 마이그레이션 버그) | 구버전 GitHub 태그(`rhasspy/piper` v1.2.0)에서 `commons.py` 원본을 그대로 가져와 로컬에 `piper_train/vits/commons.py`로 배치 |
| 4 | `piper_sample_generator "텍스트1" "텍스트2" ...` CLI가 여러 텍스트를 인자로 못 받음 | CLI의 `text` 인자가 단일 문자열만 허용 (nargs 미설정) | CLI 대신 `generate_samples_onnx()` 함수를 Python에서 직접 호출하는 스크립트로 우회 |
| 5 | 부정 샘플 생성 스크립트가 `torch.load()`로 실패 (`invalid load key`) | `.onnx` 보이스인데 `.pt` 전용 함수(`generate_samples`)를 잘못 호출함 | `generate_samples_onnx()`로 함수 교체 |
| 6 | `openwakeword.train` 실행 시 각종 `ModuleNotFoundError` 연쇄 (pronouncing, torch_audiomentations, speechbrain, mutagen 등) | 학습 스크립트가 요구하는 부속 패키지들이 기본 설치 목록에 없었음 | 에러 나는 대로 하나씩 설치 |
| 7 | `torchaudio.load()`가 `torchcodec` 요구, `torchcodec`은 시스템 `ffmpeg` 라이브러리(`libavutil.so` 등) 요구 | torchaudio 2.9+ 부터 레거시 백엔드 제거, ffmpeg 미설치 상태 | ffmpeg 설치(sudo) 대신, `openwakeword/data.py`의 `torchaudio.load()` 호출 4곳을 **soundfile 기반 커스텀 로더**로 로컬 패치 (sudo 불필요, 더 가벼움) |
| 8 | `ValueError: Error! Clip does not have the correct sample rate!` | TTS로 만든 클립이 22050Hz인데(Piper 보이스 기본값), openWakeWord는 16000Hz 고정 요구. 실제 녹음(16kHz)과 섞여서 불일치 발생 | 전체 클립(TTS 긍정/부정) 일괄 16kHz로 리샘플링하는 스크립트 실행 |
| 9 | `output` 폴더를 실수로 `rm -rf` 해서 데이터 split 유실 | 재실행 전 정리하다가 실수 | split 스크립트 재실행으로 복구 (원본 TTS/녹음 파일은 별도 보관돼있어서 데이터 손실은 없었음) |
| 10 | 학습된 모델 로딩 시 `masila.onnx.data`를 못 찾음 | PyTorch의 최신 ONNX 익스포터가 가중치를 `.onnx` 본체와 별도의 `.onnx.data` 파일로 분리 저장하는데, 패키지 배포 시 이 파일을 빠뜨림 | `setup.py`의 `glob` 패턴에 `*.onnx.data` 추가, 두 파일 다 패키지에 포함되도록 수정 |
| 11 | ROS2 노드 실행 시 마이크 인덱스 불일치 (`Invalid number of channels`) | USB 카드 번호가 재부팅/재연결 사이에 `hw:0`→`hw:2`로 바뀌면서 sounddevice 인덱스도 바뀜 | 인덱스 하드코딩 대신, 장치 이름("Brio")으로 런타임에 자동 탐색하도록 노드 코드 수정 |
| 12 | (환경 무관) `sudo apt-get install libportaudio2`, 프로젝트 전역 `colcon build`가 갑자기 안 됨 (`error: option --uninstall not recognized`) | 이전 세션에 `~/.local`에 유저 레벨로 깔린 setuptools 83.0.0이 apt의 59.6.0을 덮어써서 colcon의 legacy `setup.py develop` 방식과 충돌 (이번 작업과 무관한 잠재 버그였음) | `~/.local`의 setuptools 제거 → apt 버전(59.6.0) 정상 인식, 이후 모든 ROS2 패키지 빌드 정상화 |

---

## 4. 학습 데이터 구성

| 종류 | 개수 | 출처 |
|---|---|---|
| 긍정 (TTS) | 300 | Piper `ko_KR-kss-medium` 보이스, length_scale/noise_scale 다양화 |
| 긍정 (실제 녹음) | 67 | 본인 + 팀원 녹음 (`record_real_samples.py`, Brio 웹캠 마이크) |
| 부정 (TTS) | 400 | "마실아"와 발음이 비슷하거나 일상적인 한국어 문장 49종 합성 |
| RIR (잔향) | 270 | MIT 환경 임펄스 응답 데이터셋 (HuggingFace, 8.4MB) |
| 검증셋 | ~11시간 분량 features | openWakeWord 공식 validation_set_features.npy (184MB) |

- 전체 17GB 규모의 ACAV100M 부정 데이터셋은 용량 문제로 제외 → 대신 타겟형 부정 문장(TTS)으로 대체 (모델 강건성은 다소 낮을 수 있음, 데모 목적으로는 충분히 검증됨)

---

## 5. 학습 설정 (`masila_config.yml`)
- 모델: DNN, layer_size 32
- steps: 3000 (+ auto-training이 추가로 여러 사이클 자동 반복)
- augmentation_rounds: 3
- batch_n_per_class: positive 32 / adversarial_negative 32

## 6. 결과
- 산출물: `~/wakeword_training/output/masila.onnx` (+ `masila.onnx.data`)
- **실기 라이브 테스트 (2026-07-30): 8회 발화 중 8회 전부 감지 성공, score 0.55~0.78 (threshold 0.5)**
- `petbot_wakeword` ROS2 패키지에 반영 완료 (`wakeword_node.py`가 이 모델로 `/wakeword_detected` 발행)

## 7. 남은 참고사항
- 마이크는 임시로 웹캠(Brio) 내장 마이크 사용 중 — 전용 마이크 입고 시 `mic_device_name` 파라미터만 바꾸면 됨
- tflite 변환은 실패했으나(`onnx_tf` 모듈 없음) 미사용 — onnxruntime으로 onnx 직접 추론하므로 문제 없음
- 재학습이 필요할 경우 `~/wakeword_training/` 아래 스크립트들(`split_data.py`, `resample_to_16k.py`, `generate_negatives.py`)과 `masila_config.yml`을 그대로 재사용 가능
