# 디바이스 사진 업로드 API

원본 사진은 백엔드를 거치지 않고 디바이스가 S3에 직접 업로드한다. 백엔드는
업로드 상태와 객체 키만 `robot_photos`에 저장한다. 산책일지 결과물은
완성된 산책일지는 날짜/session 고정 경로로 별도 관리하므로 두 기능의 데이터를
섞지 않는다.

## API 흐름

| 순서 | 요청 | 인증 | 역할 |
| --- | --- | --- | --- |
| 1 | `POST /api/v1/devices/{deviceId}/images/presigned-url` | Device Token | 업로드 URL 발급 |
| 2 | `PUT {uploadUrl}` | Presigned URL | 디바이스가 S3에 직접 업로드 |
| 3 | `POST /api/v1/devices/{deviceId}/images/{imageId}/complete` | Device Token | S3 메타데이터 검증 및 완료 처리 |
| 4 | `GET /api/v1/pets/{petId}/images` | Access Token | 업로드된 사진 목록 조회 |
| 5 | `GET /api/v1/images/{imageId}/download-url` | Access Token | 다운로드 URL 발급 |

디바이스 API의 인증 헤더는 다음 형식이다.

```http
Authorization: Device {DEVICE_HTTP_TOKEN}
```

## 업로드 URL 요청

```http
POST /api/v1/devices/device-photo-001/images/presigned-url
Authorization: Device {DEVICE_HTTP_TOKEN}
Content-Type: application/json
```

```json
{
  "contentType": "image/jpeg",
  "fileSize": 204800,
  "capturedAt": "2026-08-04T09:00:00Z"
}
```

응답의 `uploadUrl`은 기본 300초 동안 유효하다. 허용 형식은 JPEG, PNG,
WebP이며 기본 최대 크기는 10 MiB다.

## S3 업로드와 완료 처리

Presigned URL을 발급할 때 서명한 `Content-Type`과 `Content-Length`를 그대로
사용해야 한다.

```powershell
Invoke-WebRequest `
  -Method Put `
  -Uri $presigned.data.uploadUrl `
  -ContentType "image/jpeg" `
  -InFile $imagePath

$completed = Invoke-RestMethod `
  -Method Post `
  -Uri "$baseUrl/v1/devices/$deviceId/images/$($presigned.data.imageId)/complete" `
  -Headers @{ Authorization = "Device $deviceToken" }
```

완료 API는 트랜잭션을 시작하기 전에 S3 `HeadObject`로 크기와 MIME 타입을
검증한다. S3 정보가 요청 당시 값과 다르면 DB 상태를 `UPLOADED`로 바꾸지 않는다.

## 로컬 자동 테스트

```powershell
cd 02_Backend
./gradlew.bat test --tests "com.ssafy.backend.robot.image.*"
```

전체 회귀 테스트는 다음 명령으로 실행한다.

```powershell
./gradlew.bat test
```
