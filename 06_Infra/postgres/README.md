# PostgreSQL 실행

## 로컬 실행

1. `.env.example`을 `.env`로 복사하고 비밀번호를 변경합니다.
2. 이 디렉터리에서 `docker compose up -d`를 실행합니다.
3. 최초 볼륨 생성 시 `init/`의 SQL 파일이 이름 순서대로 자동 실행됩니다.

백엔드의 `02_Backend/.env`에는 다음 값을 설정합니다.

```properties
DB_URL=jdbc:postgresql://localhost:5432/mysil
DB_USERNAME=mysil
DB_PASSWORD=변경한_비밀번호
```

스키마 파일을 수정해도 기존 볼륨에는 자동으로 다시 적용되지 않습니다. 개발 초기화가 필요한 경우에만 데이터를 백업한 후 볼륨을 새로 생성합니다.

## 배포 환경

운영 환경에서는 `.env` 파일을 이미지나 Git 저장소에 포함하지 않습니다. Kubernetes Secret 또는 배포 플랫폼의 Secret에 `DB_URL`, `DB_USERNAME`, `DB_PASSWORD`를 등록해 백엔드 컨테이너 환경변수로 전달합니다.

## Kubernetes 원격 배포

아래 예시는 백엔드와 PostgreSQL을 같은 네임스페이스에 배포합니다. `NAMESPACE`는 실제 사용하는 네임스페이스로 변경합니다.

### 1. Secret 생성

```powershell
kubectl -n NAMESPACE create secret generic postgres-secret `
  --from-literal=POSTGRES_DB=mysil `
  --from-literal=POSTGRES_USER=mysil `
  --from-literal=POSTGRES_PASSWORD='충분히-긴-비밀번호' `
  --dry-run=client -o yaml | kubectl apply -f -
```

비밀번호는 Git이나 셸 스크립트에 저장하지 않습니다. 이미 Secret이 있다면 `create` 대신 안전한 Secret 관리 절차로 갱신합니다.

### 2. 초기 스키마 ConfigMap 생성

저장소 루트에서 실행합니다.

```powershell
kubectl -n NAMESPACE create configmap postgres-init `
  --from-file=001_schema.sql=06_Infra/postgres/init/001_schema.sql `
  --from-file=002_robot_events.sql=06_Infra/postgres/init/002_robot_events.sql `
  --from-file=003_robot_photos.sql=06_Infra/postgres/init/003_robot_photos.sql `
  --from-file=004_robot_mqtt_runtime.sql=06_Infra/postgres/init/004_robot_mqtt_runtime.sql `
  --from-file=006_robot_qr_compat.sql=06_Infra/postgres/init/006_robot_qr_compat.sql `
  --from-file=007_pet_creation_requests_compat.sql=06_Infra/postgres/init/007_pet_creation_requests_compat.sql `
  --from-file=008_users_version_compat.sql=06_Infra/postgres/init/008_users_version_compat.sql `
  --from-file=009_walk_api.sql=06_Infra/postgres/init/009_walk_api.sql `
  --from-file=010_behavior_requests_open_unique.sql=06_Infra/postgres/init/010_behavior_requests_open_unique.sql `
  --dry-run=client -o yaml | kubectl apply -f -
```

`--from-file=키=경로` 형식으로 원본 파일명을 유지해야 PostgreSQL이
`001`부터 `010`까지 올바른 순서로 실행합니다. ConfigMap 전체 크기가 Kubernetes
제한을 넘지 않는지도 새 SQL을 추가할 때 확인합니다.

### 3. PostgreSQL 배포

개발 환경은 10Gi PVC를 사용합니다.

```powershell
kubectl -n NAMESPACE apply -k 06_Infra/postgres/k8s/dev
```

운영 환경은 30Gi PVC를 사용합니다.

```powershell
kubectl -n NAMESPACE apply -k 06_Infra/postgres/k8s/prod
```

### 4. 기동 확인

```powershell
kubectl -n NAMESPACE rollout status statefulset/postgres
kubectl -n NAMESPACE get pod,service,pvc -l app=postgres
kubectl -n NAMESPACE logs postgres-0
```

테이블 확인:

```powershell
kubectl -n NAMESPACE exec postgres-0 -- `
  psql -U mysil -d mysil -c "\dt"
```

### 5. 백엔드 배포

`dev/deployment.yaml`과 `prod/deployment.yaml`은 다음 주소로 PostgreSQL에 연결하도록 설정되어 있습니다.

```text
jdbc:postgresql://postgres:5432/mysil
```

DB가 준비된 다음 기존 CI/CD 방식으로 백엔드를 배포합니다.

### 6. 시연용 로봇 QR 프로비저닝

로컬 PostgreSQL 컨테이너가 실행 중인 상태에서 저장소 루트 기준으로
다음 명령을 실행합니다.

```bash
cd 06_Infra/postgres
chmod +x scripts/provision-robot-qr.sh
./scripts/provision-robot-qr.sh \
  PETBOT-LOCAL-0001 \
  "PetBot Local Test" \
  0.0.1
```

스크립트는 32바이트 보안 난수로 QR 토큰과 Device HTTP 토큰을 생성하고,
SHA-256 해시만 DB에 저장합니다. 출력된 `qr_token`은 QR 이미지로 만들고,
`device_token`은 로봇 보안 저장소에 한 번만 설치합니다. 기본 Device 토큰
유효기간은 365일이며 `DEVICE_TOKEN_EXPIRES_DAYS`로 조절합니다. 기존 소유
로봇도 QR이 아직 없다면 최초 프로비저닝할 수 있지만, 이미 QR이 발급된
소유 로봇의 토큰은 변경하지 않습니다.
출력되는 `qr_token`은 다시 조회할 수 없으므로 QR 이미지로 만들기 전까지
안전하게 보관합니다.

이미 등록되었거나 소유자가 있는 로봇에 Device HTTP 토큰만 최초 설정하거나
교체할 때는 다음 명령을 사용합니다.

```bash
./scripts/provision-robot-qr.sh \
  --device-token-only \
  PETBOT-LOCAL-0001
```

이 모드는 기존 `serial_number`의 `robot_credentials` 행만 찾아
`device_token_hash`, 만료 시각, 교체 시각을 갱신합니다. 로봇 소유권과 기존
QR 토큰·QR 만료 시각은 변경하지 않으며 QR 토큰을 새로 생성하거나 출력하지도
않습니다. 기존 Device 토큰은 즉시 무효화됩니다. 새 `device_token` 원문은
성공 출력에서 단 한 번만 확인할 수 있으므로 바로 로봇의 보안 저장소에
교체하고 터미널 기록도 안전하게 관리합니다.

QR 유효 기간은 기본 30일이며 필요하면 실행 전에 변경할 수 있습니다.

```bash
export QR_EXPIRES_DAYS=7
export DEVICE_TOKEN_EXPIRES_DAYS=365
```

### 주의

- 초기 SQL은 PVC가 비어 있는 최초 기동에만 자동 실행됩니다.
- 기존 PVC가 있으면 ConfigMap을 수정해도 스키마가 다시 적용되지 않습니다.
- 기존 PVC가 있는 상태에서 Secret의 비밀번호만 바꾸면 실제 DB 비밀번호는 자동 변경되지 않습니다.
- 운영 스키마 변경은 이후 Flyway 같은 마이그레이션 도구로 관리해야 합니다.
- PostgreSQL Service는 클러스터 내부 전용이며 Ingress나 NodePort로 외부에 노출하지 않습니다.
- PVC를 삭제하면 DB 데이터가 삭제될 수 있으므로 운영에서는 백업 없이 삭제하지 않습니다.
- QR 등록 Rate Limit은 현재 단일 백엔드 인스턴스 메모리에서 관리됩니다.
  백엔드 replica를 2개 이상으로 늘리기 전에 Redis 또는 API Gateway 기반으로 변경해야 합니다.
