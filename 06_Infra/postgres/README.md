# PostgreSQL 실행

## 로컬 실행

1. `.env.example`을 `.env`로 복사하고 비밀번호를 변경합니다.
2. 이 디렉터리에서 `docker compose up -d`를 실행합니다.
3. 최초 볼륨 생성 시 `init/001_schema.sql`이 자동 실행됩니다.

백엔드의 `02_Backend/.env`에는 다음 값을 설정합니다.

```properties
DB_URL=jdbc:postgresql://localhost:5432/mysil
DB_USERNAME=mysil
DB_PASSWORD=변경한_비밀번호
```

스키마 파일을 수정해도 기존 볼륨에는 자동으로 다시 적용되지 않습니다. 개발 초기화가 필요한 경우에만 데이터를 백업한 후 볼륨을 새로 생성합니다.

기존 Kubernetes PVC에는 Jenkins가 배포 직전에
`scripts/apply-migrations.sh`로 신규 마이그레이션을 실행합니다. 마이그레이션은
`ON_ERROR_STOP`으로 실행되며, 제거 대상 레거시 테이블에 데이터가 있으면
백업과 명시적인 삭제 승인 전까지 중단됩니다.

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
  --dry-run=client -o yaml | kubectl apply -f -
```

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

스크립트는 32바이트 보안 난수로 QR 원문을 생성하고, SHA-256 해시만
DB에 저장합니다. 기존 소유 로봇도 QR이 아직 없다면 최초 프로비저닝할 수
있지만, 이미 QR이 발급된 소유 로봇의 QR은 변경하지 않습니다.
출력되는 `qr_token`은 다시 조회할 수 없으므로 QR 이미지로 만들기 전까지
안전하게 보관합니다.

QR 유효 기간은 기본 30일이며 필요하면 실행 전에 변경할 수 있습니다.

```bash
export QR_EXPIRES_DAYS=7
```

### 주의

- 초기 SQL은 PVC가 비어 있는 최초 기동에만 자동 실행됩니다.
- 기존 PVC가 있으면 ConfigMap을 수정해도 스키마가 다시 적용되지 않습니다.
- 기존 PVC가 있는 상태에서 Secret의 비밀번호만 바꾸면 실제 DB 비밀번호는 자동 변경되지 않습니다.
- 운영 스키마 변경은 이후 Flyway 같은 마이그레이션 도구로 관리해야 합니다.
- `init/007_walk_diaries.sql` 이후 변경도 반드시 별도 번호의 멱등성
  마이그레이션 파일로 추가하고 Jenkins 적용 목록에 포함합니다.
- PostgreSQL Service는 클러스터 내부 전용이며 Ingress나 NodePort로 외부에 노출하지 않습니다.
- PVC를 삭제하면 DB 데이터가 삭제될 수 있으므로 운영에서는 백업 없이 삭제하지 않습니다.
- QR 등록 Rate Limit은 현재 단일 백엔드 인스턴스 메모리에서 관리됩니다.
  백엔드 replica를 2개 이상으로 늘리기 전에 Redis 또는 API Gateway 기반으로 변경해야 합니다.
