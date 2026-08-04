# 산책일지 조회 API

산책 종료 후 로봇의 전후처리가 완료되면 S3에 아래 두 객체가 저장된다.

```text
robot-images/{deviceId}/{yyyy-MM-dd}/session{N}/story_image.png
robot-images/{deviceId}/{yyyy-MM-dd}/session{N}/walk_log.md
```

로봇은 두 객체의 업로드가 끝난 뒤 `WALK_COMPLETED` MQTT 이벤트를 발행한다.
백엔드는 이벤트의 `walkDate`와 `session`을 `walk_diaries`에 기록한다.

## 산책일지 상세 조회

```http
GET /api/v1/walks/{walkId}/diary
Authorization: Bearer {ACCESS_TOKEN}
```

응답에는 `story_image.png`의 Presigned URL과 `walk_log.md`의 UTF-8 본문이
포함된다. 로그인 사용자가 소유한 반려동물의 산책만 조회할 수 있다.

`walk_log.md`는 UTF-8이어야 하며 기본 최대 크기는 1 MiB다.
운영 환경에서는 `S3_MAX_MARKDOWN_BYTES`로 최대 10 MiB까지 조정할 수 있다.
파일이 제한을 넘거나 UTF-8이 아니면 `WALK_DIARY_CONTENT_INVALID` 오류가
반환된다.

## 산책일지 피드 조회

```http
GET /api/v1/walk-diaries?beforeDate=2026-08-04&size=30
Authorization: Bearer {ACCESS_TOKEN}
```

`beforeDate`는 선택값이며 해당 날짜보다 이전 일지만 조회한다. 첫 페이지에서는
생략한다. `size`는 날짜 묶음 개수이며 기본 30, 최대 100이다. 같은 날짜의
산책은 페이지 중간에서 나뉘지 않는다.

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "walkDate": "2026-08-03",
        "walkCount": 2,
        "walks": [
          {
            "walkId": 10,
            "session": 1,
            "startedAt": "2026-08-03T04:30:00Z",
            "endedAt": "2026-08-03T05:00:00Z"
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
최신 날짜부터 날짜별 산책 횟수와 해당 날짜의 `walkId`, `session`, 산책 시간이
반환된다. 상세 조회에는 피드에서 받은 `walkId`를 사용한다.
