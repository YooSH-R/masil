# 산책일지 조회 API

로봇의 전후처리가 완료되면 S3에 아래 두 객체가 저장된다.

```text
robot-images/{deviceId}/{yyyy-MM-dd}/session{1~6}/story_image.png
robot-images/{deviceId}/{yyyy-MM-dd}/session{1~6}/walk_log.md
```

백엔드는 로그인 사용자가 현재 페어링한 로봇의 `deviceId`를 DB에서 확인한 뒤,
해당 `robot-images/{deviceId}/` prefix만 S3에서 조회한다. `walks`,
`walk_diaries`, `WALK_COMPLETED` 이벤트는 산책일지 조회에 사용하지 않는다.
최초 소유자는 로봇 등록 전에 사전 적재된 시연 일지도 조회할 수 있다. 로봇이
다른 사용자에게 재페어링된 경우에는 이전 사용자의 일지가 노출되지 않도록
현재 활성 페어링의 `paired_at` 이후 업로드된 S3 객체만 조회할 수 있다.

피드에는 `story_image.png`와 `walk_log.md`가 모두 존재하고 날짜 및 session
경로 규칙을 만족하는 일지만 노출된다.

백엔드 AWS 자격증명에는 버킷의 `s3:ListBucket` 권한과
`robot-images/*` 객체의 `s3:GetObject` 권한이 필요하다.

## 산책일지 상세 조회

```http
GET /api/v1/walk-diaries/{deviceId}/{walkDate}/{session}
Authorization: Bearer {ACCESS_TOKEN}
```

예시:

```http
GET /api/v1/walk-diaries/device-001/2026-08-03/1
```

로그인 사용자가 현재 페어링한 디바이스만 조회할 수 있다. 응답에는
`story_image.png`의 Presigned URL과 `walk_log.md`의 UTF-8 본문이 포함된다.

```json
{
  "success": true,
  "data": {
    "deviceId": "device-001",
    "walkDate": "2026-08-03",
    "session": 1,
    "imageUrl": "https://...",
    "imageUrlExpiresAt": "2026-08-05T03:05:00Z",
    "markdown": "# 오늘의 산책"
  }
}
```

`walk_log.md`는 UTF-8이어야 하며 기본 최대 크기는 1 MiB다. 운영 환경에서는
`S3_MAX_MARKDOWN_BYTES`로 최대 10 MiB까지 조정할 수 있다. 파일이 제한을
넘거나 UTF-8이 아니면 `WALK_DIARY_CONTENT_INVALID` 오류가 반환된다.

## 산책일지 피드 조회

```http
GET /api/v1/walk-diaries?beforeDate=2026-08-04&size=30
Authorization: Bearer {ACCESS_TOKEN}
```

`beforeDate`는 선택값이며 해당 날짜보다 이전 일지만 조회한다. 첫 페이지에서는
생략한다. `size`는 날짜 묶음 개수이며 기본 30, 최대 100이다. 같은 날짜의
일지는 페이지 중간에서 나뉘지 않는다.

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "walkDate": "2026-08-03",
        "walkCount": 2,
        "diaries": [
          {
            "deviceId": "device-001",
            "session": 1
          },
          {
            "deviceId": "device-001",
            "session": 2
          }
        ]
      }
    ],
    "nextCursor": "2026-08-03",
    "hasNext": true
  }
}
```

`hasNext`가 `true`이면 다음 요청의 `beforeDate`에 `nextCursor`를 전달한다.
상세 조회에는 피드에서 받은 `deviceId`, `walkDate`, `session`을 사용한다.
