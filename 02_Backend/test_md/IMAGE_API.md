# 사진 전송 HTTP API 구현 및 테스트

## 1. 현재 구현 상태

사진 파일은 백엔드를 거치지 않고 디바이스가 S3에 직접 업로드합니다. 백엔드는 Presigned URL 발급, 사진 메타데이터 저장, 업로드 완료 검증, 목록 및 다운로드 URL 발급을 담당합니다.

| 방향 | API | 구현 상태 | 역할 |
| --- | --- | --- | --- |
| 디바이스 → 백엔드 | `POST /api/v1/devices/{deviceId}/images/presigned-url` | 완료 | 업로드용 Presigned URL과 사진 ID 발급 |
| 백엔드 → 디바이스 | 위 API 응답 | 완료 | `imageId`, `objectKey`, `uploadUrl`, 만료 시각 반환 |
| 디바이스 → S3 | `PUT {uploadUrl}` | 완료된 구조 | 디바이스가 사진 파일을 S3에 직접 업로드 |
| 디바이스 → 백엔드 | `POST /api/v1/devices/{deviceId}/images/{imageId}/complete` | 완료 | S3 파일의 크기와 Content-Type을 확인한 뒤 업로드 완료 처리 |
| 앱 → 백엔드 | `GET /api/v1/pets/{petId}/images` | 완료 | 해당 반려동물의 업로드 완료 사진 목록 조회 |
| 앱 → 백엔드 | `GET /api/v1/images/{imageId}/download-url` | 완료 | 조회용 Presigned URL 발급 |

함께 구현된 항목은 다음과 같습니다.

- `robot_photos` 테이블과 인덱스 마이그레이션
- 디바이스 HTTP 토큰 인증
- 반려동물 소유권 검사
- JPEG, PNG, WebP 형식 허용
- 최대 파일 크기 10 MiB 제한
- Presigned URL 기본 유효 시간 5분
- S3 객체 키 자동 생성
  - `robot-images/{deviceId}/{yyyy}/{MM}/{imageId}.{확장자}`

현재 자동 테스트는 업로드 완료 시 S3 메타데이터 검증, 파일 크기 불일치 거부, 지원하지 않는 형식 거부, 10 MiB 초과 거부를 확인합니다.

실제 S3에 파일을 올리고 목록 및 다운로드까지 확인하는 전체 E2E 테스트는 아래 절차로 수동 확인해야 합니다.

## 2. API 명세

### 2.1 업로드 URL 요청

```http
POST /api/v1/devices/device-001/images/presigned-url
Authorization: Device {DEVICE_HTTP_TOKEN}
Content-Type: application/json
```

```json
{
  "contentType": "image/jpeg",
  "fileSize": 204800,
  "capturedAt": "2026-07-29T06:00:00Z"
}
```

현재 구현은 `fileName`을 받지 않습니다. 파일 확장자와 `objectKey`는 `contentType`을 기준으로 백엔드가 생성합니다.

응답:

```json
{
  "success": true,
  "data": {
    "imageId": "e38ec479-f956-4d4d-ad4e-278138dc1f62",
    "objectKey": "robot-images/device-001/2026/07/e38ec479-f956-4d4d-ad4e-278138dc1f62.jpg",
    "uploadUrl": "https://walk-picture-s3-483461801092-ap-northeast-2-an.s3.ap-northeast-2.amazonaws.com/...",
    "expiresAt": "2026-07-29T06:05:00Z"
  },
  "timestamp": "2026-07-29T06:00:00Z"
}
```

### 2.2 S3에 사진 업로드

Presigned URL 요청에 사용한 `contentType` 및 `fileSize`와 실제 업로드 파일이 일치해야 합니다.

```http
PUT {uploadUrl}
Content-Type: image/jpeg

{사진 바이너리}
```

### 2.3 업로드 완료 처리

요청 본문은 없습니다. 백엔드가 S3의 객체를 조회해 파일 크기와 Content-Type을 검증합니다.

```http
POST /api/v1/devices/device-001/images/{imageId}/complete
Authorization: Device {DEVICE_HTTP_TOKEN}
```

응답:

```json
{
  "success": true,
  "data": {
    "imageId": "e38ec479-f956-4d4d-ad4e-278138dc1f62",
    "deviceId": "device-001",
    "objectKey": "robot-images/device-001/2026/07/e38ec479-f956-4d4d-ad4e-278138dc1f62.jpg",
    "contentType": "image/jpeg",
    "fileSize": 204800,
    "capturedAt": "2026-07-29T06:00:00Z",
    "uploadedAt": "2026-07-29T06:01:00Z"
  },
  "timestamp": "2026-07-29T06:01:00Z"
}
```

### 2.4 앱에서 사진 목록 조회

디바이스 토큰이 아니라 로그인한 사용자의 Access Token이 필요합니다.

```http
GET /api/v1/pets/{petId}/images
Authorization: Bearer {APP_ACCESS_TOKEN}
```

### 2.5 앱에서 다운로드 URL 발급

```http
GET /api/v1/images/{imageId}/download-url
Authorization: Bearer {APP_ACCESS_TOKEN}
```

응답:

```json
{
  "success": true,
  "data": {
    "imageId": "e38ec479-f956-4d4d-ad4e-278138dc1f62",
    "downloadUrl": "https://walk-picture-s3-483461801092-ap-northeast-2-an.s3.ap-northeast-2.amazonaws.com/...",
    "expiresAt": "2026-07-29T06:10:00Z"
  },
  "timestamp": "2026-07-29T06:05:00Z"
}
```

## 3. 자동 테스트

```powershell
cd C:\Users\SSAFY\Desktop\S15P11A203\02_Backend
.\gradlew.bat --console=plain test `
  --tests "*RobotImageServiceTest" `
  --tests "*RobotImageStoreTest"
```

예상 결과:

```text
BUILD SUCCESSFUL
```

전체 백엔드 테스트:

```powershell
.\gradlew.bat --console=plain test
```

## 4. 로컬에서 실제 S3 업로드 테스트

### 4.1 사전 조건

- S3 버킷: `walk-picture-s3-483461801092-ap-northeast-2-an`
- 버킷에 `PutObject`, `GetObject`, `HeadObject` 권한을 가진 AWS 자격 증명
- 테스트할 JPEG, PNG 또는 WebP 파일
- `.env`에 실제 키를 저장하되 Git에는 올리지 않기

```dotenv
AWS_ACCESS_KEY_ID={AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY={AWS_SECRET_ACCESS_KEY}
AWS_REGION=ap-northeast-2
```

### 4.2 로컬 백엔드 실행

```powershell
cd C:\Users\SSAFY\Desktop\S15P11A203\02_Backend

Get-Content .env |
  Where-Object { $_ -match '^\s*[^#][^=]*=' } |
  ForEach-Object {
    $name, $value = $_ -split '=', 2
    [Environment]::SetEnvironmentVariable(
      $name.Trim(),
      $value.Trim(),
      "Process"
    )
  }

.\gradlew.bat bootRun --args="--spring.profiles.active=s3local"
```

`s3local` 프로필은 H2에 다음 데이터를 자동으로 생성합니다.

| 항목 | 값 |
| --- | --- |
| deviceId | `device-001` |
| Device HTTP Token | `local-device-token` |
| petId | `900001` |

Device HTTP Token은 Mosquitto 접속에 사용하는 MQTT 비밀번호와 다른 값입니다.

### 4.3 Presigned URL 요청부터 완료 처리까지

새 PowerShell 창에서 실행합니다.

```powershell
$baseUrl = "http://localhost:8080/api"
$deviceId = "device-001"
$deviceHttpToken = "local-device-token"
$imagePath = "C:\Users\SSAFY\Pictures\photo.jpg"
$contentType = "image/jpeg"

$imageFile = Get-Item $imagePath
$deviceHeaders = @{
  Authorization = "Device $deviceHttpToken"
}

$uploadRequest = @{
  contentType = $contentType
  fileSize = $imageFile.Length
  capturedAt = (Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json

$presigned = Invoke-RestMethod `
  -Method Post `
  -Uri "$baseUrl/v1/devices/$deviceId/images/presigned-url" `
  -Headers $deviceHeaders `
  -ContentType "application/json" `
  -Body $uploadRequest

$presigned.data | Format-List *

$imageId = $presigned.data.imageId
$uploadUrl = $presigned.data.uploadUrl

curl.exe `
  -X PUT `
  -H "Content-Type: $contentType" `
  --upload-file "$imagePath" `
  "$uploadUrl"

$completed = Invoke-RestMethod `
  -Method Post `
  -Uri "$baseUrl/v1/devices/$deviceId/images/$imageId/complete" `
  -Headers $deviceHeaders

$completed.data | Format-List
```

정상이라면 `uploadedAt`과 실제 `fileSize`가 출력됩니다.

### 4.4 앱용 목록 및 다운로드 테스트

앱 로그인으로 발급받은 Access Token을 입력합니다. 로컬 `s3local`의 테스트 사진은 `petId=900001`에 연결되어 있으므로, 토큰의 사용자도 해당 테스트 사용자를 가리켜야 합니다. 일반 로그인 토큰의 사용자가 다르면 소유권 검사에서 거부되는 것이 정상입니다.

```powershell
$appAccessToken = Read-Host "App Access Token"
$appHeaders = @{
  Authorization = "Bearer $appAccessToken"
}

$images = Invoke-RestMethod `
  -Method Get `
  -Uri "$baseUrl/v1/pets/900001/images" `
  -Headers $appHeaders

$images.data | Format-Table

$download = Invoke-RestMethod `
  -Method Get `
  -Uri "$baseUrl/v1/images/$imageId/download-url" `
  -Headers $appHeaders

$download.data.downloadUrl
```

출력된 `downloadUrl`을 브라우저에서 열었을 때 업로드한 사진이 보이면 전체 흐름이 정상입니다.

## 5. dev 환경 테스트 시 확인할 항목

dev에서는 로컬 테스트 토큰을 사용하지 않습니다. 테스트 전에 아래 조건이 모두 필요합니다.

1. `003_robot_photos.sql`이 PostgreSQL에 적용되어 있어야 합니다.
2. 백엔드에 `S3_ENABLED=true`, 버킷, 리전, AWS 자격 증명이 설정되어 있어야 합니다.
3. `robots`에 해당 `deviceId`가 등록되어 있어야 합니다.
4. `robot_credentials`에 Device HTTP Token의 SHA-256 해시가 저장되어 있어야 합니다.
5. `robot_pairings`에 사용자, 반려동물, 로봇의 활성 페어링이 있어야 합니다.
6. 앱 목록 및 다운로드 테스트에는 해당 반려동물 소유자의 Access Token이 필요합니다.

### 5.1 Device HTTP Token 생성

MQTT 비밀번호와 사진 HTTP API용 Device Token은 서로 다른 값입니다. 원본 토큰은 디바이스에 보관하고 DB에는 SHA-256 해시만 저장합니다.

```powershell
$randomBytes = New-Object byte[] 32
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($randomBytes)

$deviceHttpToken = [Convert]::ToBase64String($randomBytes).
  TrimEnd('=').
  Replace('+', '-').
  Replace('/', '_')

$sha256 = [Security.Cryptography.SHA256]::Create()
$hashBytes = $sha256.ComputeHash(
  [Text.Encoding]::UTF8.GetBytes($deviceHttpToken)
)
$deviceTokenHash = -join (
  $hashBytes | ForEach-Object { $_.ToString("x2") }
)

"Device HTTP Token: $deviceHttpToken"
"Device Token Hash: $deviceTokenHash"
```

### 5.2 dev 테스트 디바이스 등록

PostgreSQL에 접속합니다.

```bash
sudo k3s kubectl -n s15a203-dev exec -it postgres-0 -- \
  psql -U mysil -d mysil
```

`<USER_ID>`에는 앱 로그인 사용자의 ID를, `<DEVICE_TOKEN_HASH>`에는 PowerShell에서 생성한 64자리 해시를 넣습니다. 꺾쇠 괄호까지 그대로 입력하면 안 됩니다.

```sql
WITH new_pet AS (
    INSERT INTO pets (user_id, name)
    VALUES (<USER_ID>, 'S3 API Test Pet')
    RETURNING id, user_id
),
new_robot AS (
    INSERT INTO robots (
        serial_number,
        model_name,
        owner_user_id,
        ownership_claimed_at,
        updated_at
    )
    SELECT
        'device-photo-001',
        'DEV_PHOTO_TEST',
        user_id,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
    FROM new_pet
    RETURNING id
),
new_credential AS (
    INSERT INTO robot_credentials (
        robot_id,
        device_token_hash,
        qr_token_hash,
        created_at,
        updated_at
    )
    SELECT
        id,
        '<DEVICE_TOKEN_HASH>',
        md5('device-photo-001-qr-a')
            || md5('device-photo-001-qr-b'),
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
    FROM new_robot
    RETURNING robot_id
),
new_pairing AS (
    INSERT INTO robot_pairings (pet_id, robot_id, paired_at)
    SELECT
        new_pet.id,
        new_robot.id,
        CURRENT_TIMESTAMP
    FROM new_pet
    CROSS JOIN new_robot
    RETURNING id, pet_id, robot_id
),
new_affinity AS (
    INSERT INTO pet_affinity_states (
        pet_id,
        affinity_score,
        affinity_level,
        mood,
        last_interaction_at
    )
    SELECT
        id,
        50,
        3,
        'FRIENDLY',
        CURRENT_TIMESTAMP
    FROM new_pet
    RETURNING pet_id
)
SELECT *
FROM new_pairing;
```

출력된 `pet_id`를 앱 사진 목록 테스트에 사용합니다.

### 5.3 dev S3 업로드 테스트

로컬 PowerShell에서 실행합니다.

```powershell
$baseUrl = "http://i15a203.p.ssafy.io/api"
$deviceId = "device-photo-001"
$imagePath = "C:\Users\SSAFY\Pictures\photo.jpg"
$contentType = "image/jpeg"

$imageFile = Get-Item $imagePath
$deviceHeaders = @{
  Authorization = "Device " + $deviceHttpToken
}

$body = @{
  contentType = $contentType
  fileSize = $imageFile.Length
  capturedAt = (Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json

$presigned = Invoke-RestMethod `
  -Method Post `
  -Uri "$baseUrl/v1/devices/$deviceId/images/presigned-url" `
  -Headers $deviceHeaders `
  -ContentType "application/json" `
  -Body $body

$presigned.data | Format-List *

$imageId = $presigned.data.imageId
$uploadUrl = $presigned.data.uploadUrl

curl.exe `
  -X PUT `
  -H "Content-Type: $contentType" `
  --upload-file "$imagePath" `
  "$uploadUrl"

$completed = Invoke-RestMethod `
  -Method Post `
  -Uri "$baseUrl/v1/devices/$deviceId/images/$imageId/complete" `
  -Headers $deviceHeaders

$completed.data | Format-List *
```

다음 값이 출력되면 S3 업로드와 완료 처리가 정상입니다.

- `imageId`
- `objectKey`
- `fileSize`
- `capturedAt`
- `uploadedAt`

### 5.4 dev 테스트 확인 결과

- `S3_ENABLED=true`
- S3 버킷 및 `backend-s3-secret` 연결 확인
- Device Token SHA-256 인증 확인
- Presigned URL과 `imageId`, `objectKey` 발급 확인
- PostgreSQL에 시간 값을 저장할 때 `Instant`를 `Timestamp`로 변환하도록 수정
- `RobotImageStoreTest`, `RobotImageServiceTest` 통과

실제 Device HTTP Token 원문은 DB나 Git에 저장하면 안 됩니다. 원본을 잃어버렸다면 새 토큰을 발급하고 DB의 해시를 갱신해야 합니다.

## 6. 자주 발생하는 오류

| 증상 | 확인할 내용 |
| --- | --- |
| `401 Unauthorized` | `Authorization: Device ...` 형식, deviceId와 토큰 해시 일치 여부, 백엔드 오류 로그 |
| Presigned URL API가 `404` | `S3_ENABLED=true`인지 확인 |
| S3 PUT이 `403` | URL 만료 여부, 요청한 Content-Type과 PUT의 Content-Type 일치 여부 |
| 완료 API 실패 | 실제 파일 크기 및 Content-Type이 최초 요청 값과 같은지 확인 |
| 사진 목록이 비어 있음 | 완료 API 호출 여부와 `upload_status=UPLOADED` 여부 |
| 목록 또는 다운로드가 거부됨 | Access Token 사용자가 해당 반려동물의 소유자인지 확인 |
