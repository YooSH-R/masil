## 요약 (Summary)

로봇 디바이스의 행동 이벤트·heartbeat·행동 요청 결과를 MQTT로 처리합니다.
호감도 변경과 서버 행동 요청을 디바이스 토픽으로 발행하며, 메시지 처리 오류가 MQTT 재접속 루프로 이어지지 않도록 채널 예외를 격리합니다.

## 변경 유형 (Type of change)

- [x] 🚀 기능 추가 (feat)
- [x] 🐛 버그 수정 (fix)
- [x] 📝 문서 (docs)
- [x] 🧪 테스트 (test)
- [x] ⚙️ 설정/빌드 (chore)

## 반영 브랜치

`feat/BE/robot_MQTT_API` → `dev`

## 주요 변경 내용 (What changed)

- Mosquitto StatefulSet, PVC, 인증 Secret 및 ACL 구성
- 디바이스 이벤트·heartbeat·요청 결과 MQTT 수신
- 행동 이벤트 저장과 호감도 증감 후 `/affection` 발행
- `PLAY_REQUEST`, `WALK_REQUEST`, `CARE_REQUEST`, `INTERACTION_REQUEST` 생성
- 호감도에 따른 상호작용 주기와 수면 모드 예외 적용
- inbound/outbound 채널 핸들러 명시적 연결
- 처리 실패 메시지 폐기 및 MQTT 재접속 루프 방지
- S3 Presigned URL 기반 이미지 업로드 API
- MQTT/S3 DB 마이그레이션 및 자동화 테스트 추가

## DB 적용

기존 dev DB에는 아래 SQL이 적용되어 있어야 합니다.

```bash
kubectl -n s15a203-dev exec -i postgres-0 -- \
  psql -U "$DB_USER" -d mysil \
  < 06_Infra/postgres/init/002_robot_events.sql

kubectl -n s15a203-dev exec -i postgres-0 -- \
  psql -U "$DB_USER" -d mysil \
  < 06_Infra/postgres/init/004_robot_mqtt_runtime.sql
```

## 리뷰어 테스트 방법 (How to test)

### 1. 자동 테스트

```powershell
cd 02_Backend
.\gradlew.bat --console=plain test
```

예상 결과:

```text
BUILD SUCCESSFUL
```

### 2. SSH 터널

```powershell
ssh `
  -i C:\path\to\key.pem `
  -N -T -q `
  -o ExitOnForwardFailure=yes `
  -L 127.0.0.1:11883:127.0.0.1:31883 `
  ubuntu@<EC2_PUBLIC_IP>
```

### 3. 로컬 MQTT pub/sub

`02_Backend/.env`에 backend MQTT 계정을 설정하고 실행합니다.
디바이스 비밀번호는 프롬프트에서 입력하며 저장되지 않습니다.

```powershell
powershell -ExecutionPolicy Bypass -File `
  .\06_Infra\mosquitto\scripts\Test-LocalMqttPubSub.ps1
```

예상 결과:

```text
[PASS] device -> broker -> backend subscriber
[PASS] backend -> broker -> device subscriber
[PASS] MQTT local pub/sub test completed
```

### 4. dev 배포 확인

```bash
kubectl -n s15a203-dev get pod -l app=backend
kubectl -n s15a203-dev logs deployment/backend --since=5m
```

확인 항목:

- Backend Pod `1/1 Running`
- `mqttInbound` 시작
- inbound/outbound 채널 subscriber 각 1개
- `Dispatcher has no subscribers` 없음
- `Lost connection` 반복 없음

## MQTT 주요 토픽

| 방향 | 토픽 |
|---|---|
| 디바이스 → 서버 | `robot-pet/v1/devices/{deviceId}/events` |
| 디바이스 → 서버 | `robot-pet/v1/devices/{deviceId}/heartbeat` |
| 디바이스 → 서버 | `robot-pet/v1/devices/{deviceId}/request-results` |
| 서버 → 디바이스 | `robot-pet/v1/devices/{deviceId}/affection` |
| 서버 → 디바이스 | `robot-pet/v1/devices/{deviceId}/requests` |

## 체크리스트

- [ ] 전체 Gradle 테스트 통과
- [ ] 로컬 MQTT 양방향 pub/sub 통과
- [ ] dev DB 마이그레이션 확인
- [ ] dev Pod 및 MQTT 연결 로그 확인
- [ ] MQTT/S3 비밀번호와 AWS 키가 커밋되지 않았는지 확인
- [ ] 등록된 로봇·활성 페어링으로 호감도 왕복 확인
