# 산책 API 구현 및 테스트

애플리케이션 context path가 `/api`이므로 로컬·prod 호출 경로는
`/api/v1/...`입니다. dev Ingress가 `/dev` prefix를 붙이는 배포에서는
`/dev/api/v1/...`로 호출합니다. 컨트롤러 내부 경로는 `/v1/...`입니다.

## API 계약

| 인증 | Method | Endpoint | 성공 응답 |
| --- | --- | --- | --- |
| User Access Token | GET | `/v1/walk-proposals/current` | 제안 `200`, 없음 `204` |
| User Access Token | POST | `/v1/walk-proposals/{proposalId}/responses` | `204` |
| User Access Token | POST | `/v1/walks` | `201` |
| Device Access Token | POST | `/v1/walks/{walkId}/start` | `200` |
| User Access Token | POST | `/v1/walks/{walkId}/locations/batch` | `200` |
| Device Access Token | POST | `/v1/walks/{walkId}/end` | `200` |
| User Access Token | GET | `/v1/walks/{walkId}` | `200` |
| User Access Token | GET | `/v1/walks?cursor=&limit=20` | `200` |
| User Access Token | GET | `/v1/walks/{walkId}/summary` | `200` |

제안 응답은 `ACCEPTED` 또는 `DECLINED`, 산책 상태는
`READY → ACTIVE → PROCESSING → COMPLETED`를 사용합니다.

### 산책 종료와 행동 이벤트 연동

`POST /v1/walks/{walkId}/end`가 산책을 최초로 `COMPLETED` 상태로
전환하면 같은 DB 트랜잭션에서 내부 `WALK_COMPLETED` 행동 이벤트를
저장하고 호감도를 최대 10점 올립니다. 트랜잭션이 커밋된 뒤에는 기존
`robot-pet/v1/devices/{deviceId}/affection` 토픽으로 변경된 호감도를
발행합니다.

```text
Device POST /walks/{walkId}/end
  → walks COMPLETED
  → device_events WALK_COMPLETED 저장
  → pet_affinity_states +10
  → DB commit
  → MQTT /affection 발행
```

저장되는 행동 이벤트의 `data`에는 다음 종료 시점 스냅샷이 들어갑니다.

```json
{
  "walkId": 501,
  "durationSeconds": 1200,
  "distanceMeters": 850
}
```

이벤트 `messageId`는 `walk-completed:v1:{walkId}`를 기준으로 안정적으로
생성하며, 실제 상태 전환이 일어난 경우에만 이벤트를 처리합니다. 따라서 같은
종료 API를 재호출해도 `WALK_COMPLETED` 저장과 호감도 증가는 한 번뿐입니다.

`.../events` 토픽은 디바이스에서 백엔드로 보내는 전용 토픽이므로 백엔드가
산책 완료 메시지를 자기 자신에게 다시 발행하지 않습니다. 산책 완료의 기준은
HTTP `/end` 호출 하나로 통일하며, 디바이스는 `/end` 성공 후 별도의
`WALK_COMPLETED` MQTT 이벤트를 보내면 안 됩니다. 두 경로를 동시에 사용하면
서로 다른 메시지 ID로 호감도가 중복 반영될 수 있습니다.

완료 후 늦게 도착한 GPS를 허용하는 120초 동안 거리가 다시 계산될 수 있으므로,
행동 이벤트의 거리 값은 `/end` 처리 시점의 스냅샷입니다. 최종 경로와 거리는
산책 요약 API를 기준으로 확인합니다.

### 산책 제안 생성 주체

이 API는 `walk_proposals`에 생성된 제안을 조회·응답·산책 세션으로 전환합니다.
제안 생성 자체는 HTTP 공개 API로 제공하지 않습니다.

`WalkProposalCreationService.createIfDueForRobot(robotId, now)`가 제안 생성의
내부 트랜잭션 경계입니다. 활성 페어링을 잠근 뒤 다음 조건을 모두 만족할 때만
30분 TTL의 `PENDING` 제안을 만듭니다.

- 최근 72시간 안에 완료된 산책이 없음
- `READY`, `ACTIVE`, `PROCESSING` 산책이 없음
- 아직 산책으로 전환되지 않은 `ACCEPTED` 제안이 없음
- 기존 `PENDING` 제안이 없음
- 로봇 모드가 `SLEEP`, `SLEEPING`, `ASLEEP`이 아님

최종 중복 방지는 PostgreSQL의 `uq_walk_proposals_pairing_pending` 부분 고유
인덱스가 담당합니다. 서비스는 페어링 행을 비관적 잠금하므로 같은 서비스를 통한
동시 호출은 하나씩 처리됩니다. 만료된 `PENDING`이 있으면 기존 제안 응답 흐름과
같은 `proposal → pairing` 순서로 잠근 뒤 `EXPIRED`로 바꾸고 새 제안을 생성합니다.
잠금 순서를 통일해 제안 응답과 자동 생성 사이의 교착 가능성을 줄입니다.

독립적인 산책 제안 생성 스케줄러는 두지 않습니다. 별도 스케줄러를 72시간 조건만으로
실행하면 만료·거절 직후 제안이 반복 생성되고 MQTT `WALK_REQUEST`와 서로 다른
주기로 중복될 수 있기 때문입니다. MQTT 기능을 병합할 때
`BehaviorRequestScheduler`가 `WALK_REQUEST`를 DB에 저장하는 같은 트랜잭션에서
위 메서드를 호출해야 합니다. 이 메서드는 DB 작업만 수행하고 MQTT 발행 같은 외부
네트워크 I/O는 수행하지 않습니다. MQTT 발행은 기존처럼 트랜잭션 커밋 이후에
처리합니다.

연동 시에는 먼저 `createIfDueForRobot`의 결과를 확인하고, `CREATED` 또는
`ALREADY_PENDING`인 경우에만 열린 `WALK_REQUEST`가 없을 때 새 요청을 저장합니다.
`EXPIRED_PENDING_AWAITING_CLEANUP`은 페어링 잠금 직전 외부 경로가 만료 행을
삽입한 예외적인 경합에서만 반환되며, 만료 스케줄러가 정리할 때까지 이번 주기를
건너뜁니다. 나머지 결과는 수면, 최근 산책, 진행 중 산책처럼 제안하면 안 되는 이유를
나타냅니다. 이렇게 해야 유효한 HTTP 제안 없이 MQTT 요청만 발행되는 불일치를
피할 수 있습니다.

해당 연동이 배포되지 않은 환경에서는 `GET /walk-proposals/current`가 정상적으로
`204 No Content`를 반환합니다. 설정값은 다음과 같습니다.

```text
WALK_PROPOSAL_PRODUCER_DUE_AFTER=72h
WALK_PROPOSAL_PRODUCER_TTL=30m
WALK_PROPOSAL_REQUEST_RETRY_COOLDOWN=3h
WALK_PROPOSAL_PRODUCER_SLEEPING_MODES=SLEEP,SLEEPING,ASLEEP
```

`REJECTED` 또는 `EXPIRED` 요청 직후 제안과 MQTT 알림이 매분 다시 생성되지 않도록,
최근 `WALK_REQUEST`는 상태와 관계없이 기본 3시간 동안 재생성을 막습니다.
다중 서버에서도 같은 로봇의 요청 생성은 DB 행 잠금으로 직렬화합니다.

사용자 명령은 `Authorization: Bearer {JWT}`, 시작·종료는
`Authorization: Device {DEVICE_HTTP_TOKEN}` 헤더를 사용합니다. Device 토큰은
SHA-256 해시를 `robot_credentials.device_token_hash`에 프로비저닝해야 하며,
평문 토큰은 DB에 저장하지 않습니다. 로컬 제조·등록 테스트에서는
`06_Infra/postgres/scripts/provision-robot-qr.sh`가 QR 토큰과 Device 토큰을
함께 발급합니다.

## 위치 배치 규칙

```json
{
  "points": [
    {
      "latitude": 37.5665,
      "longitude": 126.978,
      "accuracy": 12.5,
      "sequence": 1,
      "recordedAt": "2026-08-01T10:05:05Z"
    }
  ]
}
```

- 디바이스는 5초마다 측정하고 직전 채택 지점에서 5m 이상 이동한 좌표를
  버퍼링한 뒤 약 30초마다 전송합니다.
- 서버는 한 요청에 1~100개를 받으며 `accuracy > 50m`인 점은 저장하지 않고
  `rejectedCount`에 포함합니다.
- `(walkId, sequence)`가 같고 본문도 같으면 중복 저장하지 않습니다. 같은
  sequence에 다른 좌표가 오면 `409 WALK_LOCATION_SEQUENCE_CONFLICT`입니다.
- `X-Idempotency-Key`가 있으면 최초 배치 결과를 저장해 재전송 시 그대로
  반환합니다. 같은 키에 다른 본문은 `409 IDEMPOTENCY_KEY_REUSED`입니다.
- 앱이 산책 완료를 확인한 뒤 마지막 버퍼를 전송할 수 있도록 완료 후
  기본 120초 동안 `endedAt` 이전 좌표를 허용하고 거리를 다시 계산합니다.

완료 후 허용 시간은 다음 환경값으로 조절할 수 있습니다.

```text
WALK_LOCATION_LATE_GRACE_SECONDS=120
```

### GPS 배치 멱등성 보존 기간

`walk_location_batch_requests`는 `X-Idempotency-Key`의 최초 응답을 보관합니다.
설정한 보존 기간이 지난 레코드는 스케줄러가 제한된 개수만 삭제하므로, 정리
작업이 큰 트랜잭션을 만들지 않습니다. `COMPLETED` 또는 `CANCELLED` 산책이고
산책의 마지막 갱신 시각도 보존 기간을 지난 경우만 정리합니다. 따라서 장시간
진행된 산책과 완료 직후 재시도의 키는 유지됩니다. 기본 보존 기간은 30일,
실행 주기는 1시간, 회당 삭제 상한은 1,000개입니다.

```text
WALK_LOCATION_BATCH_REQUEST_RETENTION_SECONDS=2592000
WALK_LOCATION_BATCH_REQUEST_CLEANUP_SCHEDULER_ENABLED=true
WALK_LOCATION_BATCH_REQUEST_CLEANUP_DELAY_MS=3600000
WALK_LOCATION_BATCH_REQUEST_CLEANUP_BATCH_SIZE=1000
```

최초 배치 응답을 그대로 받아야 하는 재시도는 보존 기간 안에 같은 멱등성 키를
사용해야 합니다. 자동화 테스트에서는 백그라운드 정리가 테스트 데이터를
바꾸지 않도록 이 스케줄러를 비활성화합니다.

Spring 설정 키는 `walk.location-late-grace-seconds`이며 환경 변수 바인딩도
동일하게 적용됩니다.

## 기존 dev DB 마이그레이션

신규 PostgreSQL 볼륨에는 `001_schema.sql`이 적용됩니다. 이미 생성된 PVC에는
init SQL이 다시 실행되지 않으므로 배포 전에 다음 forward migration을 수동
적용해야 합니다.

최신 dev의 `007_pet_creation_requests_compat.sql`, `008_users_version_compat.sql`
다음 순서로 `009_walk_api.sql`, `010_behavior_requests_open_unique.sql`을
적용합니다. 앞선 마이그레이션이 아직 적용되지 않은 환경에서는 파일 번호
순서대로 먼저 적용합니다.

적용 순서는 반드시 **DB 백업 → `009`, `010` 성공 확인 → 백엔드 롤아웃**입니다.
마이그레이션은 관련 테이블을 잠근 뒤 기존 상태값, 생명주기, 중복 `PENDING` 제안,
중복 열린 산책, GPS 정확도를 먼저 검사합니다. 잘못된 데이터가 있으면 일부만
적용하지 않고 전체를 롤백하며 원인을 포함한 오류로 중단합니다.

```bash
DB_USER=$(kubectl -n s15a203-dev get secret postgres-secret \
  -o jsonpath='{.data.POSTGRES_USER}' | base64 --decode)

for migration in \
  06_Infra/postgres/init/009_walk_api.sql \
  06_Infra/postgres/init/010_behavior_requests_open_unique.sql
do
  kubectl -n s15a203-dev exec -i postgres-0 -- \
    psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d mysil \
    < "$migration"
done
```

적용 전 열린 산책이나 기존 상태 문자열이 있는지 확인하고 DB를 백업합니다.
마이그레이션은 `walks.started_at`의 NOT NULL을 해제하고 상태 CHECK, 활성 산책
부분 고유 인덱스, GPS 제약 및 배치 멱등성 테이블을 생성합니다.

## 로컬 테스트

JDK 17에서 실행합니다.

```powershell
cd 02_Backend
$env:JAVA_HOME = "C:\Program Files\Java\jdk-17"
.\gradlew.bat test --tests "com.ssafy.backend.walk.*"
```

통합 테스트는 다음을 검증합니다.

- 제안 조회·수락·산책 생성·시작·좌표 배치·종료·요약 전체 흐름
- User/Device 토큰 권한 분리와 타 사용자 리소스 은닉
- 같은 요청 재전송, 같은 sequence 충돌, 멱등성 키 재사용 충돌
- 50m 초과 GPS 제외와 완료 직후 마지막 GPS flush
- Haversine 거리 계산 및 경로 sequence 정렬
- 산책 종료 시 `WALK_COMPLETED` 1건 저장과 호감도 +10 반영
- 동일 종료 요청 재전송 시 이벤트와 호감도가 중복 반영되지 않음
