# 로봇 펫 MQTT 메시지 명세

모든 메시지는 JSON이며 QoS 1을 사용한다. 토픽의 `{deviceId}`와 메시지 본문의
`deviceId`는 반드시 같아야 한다. 시간은 UTC ISO-8601 형식을 사용한다.

## 디바이스에서 서버로 보내는 메시지

### 행동 이벤트

토픽:

```text
robot-pet/v1/devices/{deviceId}/events
```

```json
{
  "messageId": "550e8400-e29b-41d4-a716-446655440000",
  "messageVersion": "1.0",
  "deviceId": "device-001",
  "occurredAt": "2026-07-30T00:00:00Z",
  "eventType": "WALK_COMPLETED",
  "data": {}
}
```

`eventType`과 기본 호감도 변화:

| eventType | 변화량 |
|---|---:|
| `CALL_AND_RESPONSE` | +2 |
| `WALK_COMPLETED` | +10 |
| `CARE_ACTION` | +3 |
| `NEGATIVE_REACTION` | -3 |
| `LONG_INACTIVITY` | -1 |

호감도는 0에서 100 사이로 제한된다. 동일한 `messageId`는 다시 저장하거나
호감도를 중복 변경하지 않는다.

### Heartbeat

토픽:

```text
robot-pet/v1/devices/{deviceId}/heartbeat
```

```json
{
  "messageId": "61b2e6bb-bd1a-48fd-9156-31780e52916c",
  "messageVersion": "1.0",
  "deviceId": "device-001",
  "occurredAt": "2026-07-30T00:01:00Z",
  "batteryLevel": 75,
  "docked": false,
  "mode": "IDLE"
}
```

`batteryLevel`은 0에서 100 사이여야 한다. 서버는 최근 상태, 배터리, 충전 여부,
모드와 마지막 접속 시간을 저장한다.

### 행동 요청 처리 결과

토픽:

```text
robot-pet/v1/devices/{deviceId}/request-results
```

```json
{
  "messageId": "fb44b3da-4f27-4638-bbd0-4814fcc499cf",
  "messageVersion": "1.0",
  "deviceId": "device-001",
  "requestId": "3d05a906-31c1-4ec0-975f-54eb69fe2044",
  "status": "COMPLETED",
  "occurredAt": "2026-07-30T00:05:00Z",
  "data": {}
}
```

지원 상태:

| status | 의미 |
|---|---|
| `RECEIVED` | 디바이스가 요청을 수신함 |
| `COMPLETED` | 디바이스가 요청을 완료함 |
| `REJECTED` | 디바이스가 요청을 거절하거나 처리하지 못함 |

## 서버에서 디바이스로 보내는 메시지

### 호감도 변경

토픽:

```text
robot-pet/v1/devices/{deviceId}/affection
```

```json
{
  "messageId": "dd9e7f53-1682-4845-a730-718db56d73f0",
  "messageVersion": "1.0",
  "deviceId": "device-001",
  "eventMessageId": "550e8400-e29b-41d4-a716-446655440000",
  "previousScore": 45,
  "scoreChange": 10,
  "currentScore": 55,
  "affinityLevel": 3,
  "mood": "FRIENDLY",
  "occurredAt": "2026-07-30T00:00:01Z"
}
```

호감도 레벨은 1에서 5 사이이며 mood는 `WARY`, `CALM`, `FRIENDLY`,
`HAPPY` 중 하나다.

### 행동 요청

토픽:

```text
robot-pet/v1/devices/{deviceId}/requests
```

```json
{
  "requestId": "3d05a906-31c1-4ec0-975f-54eb69fe2044",
  "messageVersion": "1.0",
  "deviceId": "device-001",
  "requestType": "WALK_REQUEST",
  "message": "오랫동안 산책하지 않았어요. 함께 산책해요.",
  "createdAt": "2026-07-30T00:02:00Z",
  "expiresAt": "2026-07-30T00:32:00Z"
}
```

지원 요청:

| requestType | 생성 기준 |
|---|---|
| `CARE_REQUEST` | 배터리 20% 이하 |
| `WALK_REQUEST` | 최근 산책으로부터 72시간 이상 |
| `PLAY_REQUEST` | 최근 놀이·호출 응답으로부터 24시간 이상 |
| `INTERACTION_REQUEST` | 호감도별 상호작용 제한시간 초과 |

상호작용 제한시간:

| 호감도 | 요청 주기 |
|---:|---:|
| 0~20 | 24시간 |
| 21~40 | 12시간 |
| 41~60 | 6시간 |
| 61~80 | 4시간 |
| 81~100 | 3시간 |

처리되지 않은 같은 유형의 요청이 있으면 새 요청을 만들지 않는다. 요청 유효기간은
30분이며 만료 후 조건이 계속 충족되면 다시 생성할 수 있다. Heartbeat의 `mode`가
`SLEEP`, `SLEEPING`, `ASLEEP`이면 모든 행동 요청 생성을 보류하고, 깨어난 후 다음
스케줄 순회에서 다시 검사한다.

## 테스트 방법

### 자동 테스트

실제 MQTT Broker나 AWS 연결 없이 메시지 라우팅, 호감도 계산, 요청 주기,
수면 예외와 H2 데이터베이스 저장을 검증한다.

```bash
cd 02_Backend
./gradlew test
```

예상 결과:

```text
BUILD SUCCESSFUL
```

주요 테스트 클래스:

| 테스트 | 검증 내용 |
|---|---|
| `RobotMqttMessageHandlerTest` | 토픽별 DTO 변환 및 deviceId 검증 |
| `RobotMqttApplicationServiceTest` | 이벤트 저장, 호감도 계산 및 발행 |
| `BehaviorRequestSchedulerTest` | 요청 주기, 중복 방지 및 수면 모드 보류 |
| `RobotMqttStoreIntegrationTest` | H2 DB 저장과 요청 상태 전이 |

### 로컬 MQTT 송수신 테스트

#### 1. dev Broker로 SSH 터널 연결

아래 명령은 별도 터미널에서 계속 실행한다.

```bash
ssh -L 1883:localhost:31883 ubuntu@<EC2_PUBLIC_IP>
```

#### 2. 로컬 환경변수 설정

`02_Backend/.env`에 아래 값을 추가한다. 비밀번호 파일은 Git에 커밋하지 않는다.

```properties
MQTT_ENABLED=true
MQTT_URL=tcp://localhost:1883
MQTT_CLIENT_ID=robot-pet-backend-<본인이름>
MQTT_USERNAME=backend
MQTT_PASSWORD=<백엔드 MQTT 비밀번호>
MQTT_REQUEST_SCHEDULER_ENABLED=true
MQTT_REQUEST_SCHEDULER_DELAY_MS=60000
MQTT_REQUEST_SCHEDULER_INITIAL_DELAY_MS=60000
```

각 실행자의 `MQTT_CLIENT_ID`는 서로 달라야 한다.

#### 3. Spring 실행

```bash
cd 02_Backend
./gradlew bootRun --args="--spring.profiles.active=s3local"
```

로컬 H2에는 `device-001`과 호감도 50점이 테스트 데이터로 등록된다.

#### 4. 서버 발행 토픽 구독

별도 터미널에서 디바이스 계정으로 실행한다.

```bash
mosquitto_sub \
  -h localhost \
  -p 1883 \
  -u device-001 \
  -P '<디바이스 MQTT 비밀번호>' \
  -t 'robot-pet/v1/devices/device-001/affection' \
  -t 'robot-pet/v1/devices/device-001/requests' \
  -v
```

#### 5. 행동 이벤트와 호감도 응답 확인

```bash
mosquitto_pub \
  -h localhost \
  -p 1883 \
  -u device-001 \
  -P '<디바이스 MQTT 비밀번호>' \
  -t 'robot-pet/v1/devices/device-001/events' \
  -q 1 \
  -m '{
    "messageId":"550e8400-e29b-41d4-a716-446655440000",
    "messageVersion":"1.0",
    "deviceId":"device-001",
    "occurredAt":"2026-07-30T00:00:00Z",
    "eventType":"WALK_COMPLETED",
    "data":{}
  }'
```

구독 터미널의 `/affection` 메시지에서 아래 값을 확인한다.

```text
previousScore: 50
scoreChange: 10
currentScore: 60
affinityLevel: 4
```

같은 메시지를 다시 발행했을 때 `currentScore`가 추가로 증가하지 않아야 한다.

#### 6. 수면 모드 요청 보류 확인

Spring 실행 후 첫 스케줄 실행 전에 heartbeat를 발행한다.

```bash
mosquitto_pub \
  -h localhost \
  -p 1883 \
  -u device-001 \
  -P '<디바이스 MQTT 비밀번호>' \
  -t 'robot-pet/v1/devices/device-001/heartbeat' \
  -q 1 \
  -m '{
    "messageId":"61b2e6bb-bd1a-48fd-9156-31780e52916c",
    "messageVersion":"1.0",
    "deviceId":"device-001",
    "occurredAt":"2026-07-30T00:01:00Z",
    "batteryLevel":10,
    "docked":false,
    "mode":"SLEEPING"
  }'
```

1분 이상 기다려도 `/requests` 메시지가 발행되지 않아야 한다.

#### 7. 기상 후 행동 요청 확인

새로운 `messageId`와 현재 시간으로 heartbeat를 발행한다.

```bash
mosquitto_pub \
  -h localhost \
  -p 1883 \
  -u device-001 \
  -P '<디바이스 MQTT 비밀번호>' \
  -t 'robot-pet/v1/devices/device-001/heartbeat' \
  -q 1 \
  -m '{
    "messageId":"e4925ba1-cfb7-46b7-9fc9-36cc2c032402",
    "messageVersion":"1.0",
    "deviceId":"device-001",
    "occurredAt":"2026-07-30T00:03:00Z",
    "batteryLevel":10,
    "docked":false,
    "mode":"IDLE"
  }'
```

다음 스케줄 순회에서 `/requests`로 `CARE_REQUEST`가 발행되어야 한다.

#### 8. 행동 요청 결과 전송

앞에서 받은 `requestId`를 사용한다.

```bash
mosquitto_pub \
  -h localhost \
  -p 1883 \
  -u device-001 \
  -P '<디바이스 MQTT 비밀번호>' \
  -t 'robot-pet/v1/devices/device-001/request-results' \
  -q 1 \
  -m '{
    "messageId":"fb44b3da-4f27-4638-bbd0-4814fcc499cf",
    "messageVersion":"1.0",
    "deviceId":"device-001",
    "requestId":"<수신한 requestId>",
    "status":"COMPLETED",
    "occurredAt":"2026-07-30T00:05:00Z",
    "data":{}
  }'
```

Spring 로그에 예외가 없으면 처리가 완료된 것이다. 실제 DB 저장 및 상태 변경은
`RobotMqttStoreIntegrationTest`에서 자동 검증한다.

### dev 데이터베이스 마이그레이션

기존 dev 데이터베이스에는 MQTT 런타임 컬럼을 한 번 적용해야 한다.

```bash
DB_USER=$(kubectl -n s15a203-dev get secret postgres-secret \
  -o jsonpath='{.data.POSTGRES_USER}' | base64 --decode)

kubectl -n s15a203-dev exec -i postgres-0 -- \
  psql -U "$DB_USER" -d mysil \
  < 06_Infra/postgres/init/004_robot_mqtt_runtime.sql
```
