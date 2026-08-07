package com.ssafy.backend.walk.diary;

import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.http.AbortableInputStream;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Response;
import software.amazon.awssdk.services.s3.model.S3Exception;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;
import software.amazon.awssdk.services.s3.presigner.model.PresignedGetObjectRequest;

import java.io.ByteArrayInputStream;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class WalkDiaryServiceTest {

    private static final Instant PAIRED_AT =
            Instant.parse("2026-08-01T00:00:00Z");
    private static final Instant UPLOADED_AT =
            Instant.parse("2026-08-04T00:00:00Z");

    private WalkDiaryStore store;
    private S3Client s3Client;
    private S3Presigner presigner;
    private WalkDiaryService service;

    @BeforeEach
    void setUp() throws Exception {
        store = mock(WalkDiaryStore.class);
        s3Client = mock(S3Client.class);
        presigner = mock(S3Presigner.class);
        service = new WalkDiaryService(
                store,
                s3Client,
                presigner,
                new WalkDiaryS3Properties(
                        true,
                        "test-bucket",
                        "ap-northeast-2",
                        300,
                        10_485_760,
                        1024,
                        2,
                        5
                )
        );

        byte[] markdown = "# 오늘의 산책".getBytes(StandardCharsets.UTF_8);
        when(s3Client.getObject(any(GetObjectRequest.class)))
                .thenAnswer(ignored -> responseStream(markdown));
        PresignedGetObjectRequest signed =
                mock(PresignedGetObjectRequest.class);
        when(signed.url()).thenReturn(new URL("https://example.com/story.png"));
        when(presigner.presignGetObject(any(GetObjectPresignRequest.class)))
                .thenReturn(signed);
        stubObjects(
                key("2026-08-03", 1, "story_image.png"),
                key("2026-08-03", 1, "walk_log.md")
        );
    }

    /** presign URL 을 키에서 만들어, 어느 객체가 어떤 순서로 서명됐는지 본다. */
    private void stubPresignerEchoingKey() {
        when(presigner.presignGetObject(any(GetObjectPresignRequest.class)))
                .thenAnswer(invocation -> {
                    GetObjectPresignRequest request = invocation.getArgument(0);
                    PresignedGetObjectRequest signed =
                            mock(PresignedGetObjectRequest.class);
                    when(signed.url()).thenReturn(new URL(
                            "https://example.com/"
                                    + request.getObjectRequest().key()
                    ));
                    return signed;
                });
    }

    @Test
    void returnsEveryEventImageInFileNameOrder() {
        when(store.findActiveOwnedDevice(10L, "device-001"))
                .thenReturn(java.util.Optional.of(ownedDevice(PAIRED_AT)));
        stubPresignerEchoingKey();
        // S3 목록 순서를 믿지 않는다는 것을 보이려고 일부러 뒤섞어 넣는다.
        stubObjects(
                key("2026-08-07", 1, "event_03.png"),
                key("2026-08-07", 1, "event_01.png"),
                key("2026-08-07", 1, "walk_log.md"),
                key("2026-08-07", 1, "event_04.png"),
                key("2026-08-07", 1, "event_02.png")
        );

        WalkDiaryService.DiaryDetail result = service.getDiary(
                10L,
                "device-001",
                LocalDate.parse("2026-08-07"),
                1
        );

        assertEquals(
                List.of(
                        "https://example.com/" + key("2026-08-07", 1, "event_01.png"),
                        "https://example.com/" + key("2026-08-07", 1, "event_02.png"),
                        "https://example.com/" + key("2026-08-07", 1, "event_03.png"),
                        "https://example.com/" + key("2026-08-07", 1, "event_04.png")
                ),
                result.imageUrls()
        );
        // imageUrl 은 배포된 앱 호환용으로 첫 장을 가리킨다.
        assertEquals(result.imageUrls().getFirst(), result.imageUrl());
    }

    @Test
    void stillReadsLegacySessionWithSingleStoryImage() {
        when(store.findActiveOwnedDevice(10L, "device-001"))
                .thenReturn(java.util.Optional.of(ownedDevice(PAIRED_AT)));
        stubPresignerEchoingKey();
        stubObjects(
                key("2026-08-03", 1, "story_image.png"),
                key("2026-08-03", 1, "walk_log.md")
        );

        WalkDiaryService.DiaryDetail result = service.getDiary(
                10L,
                "device-001",
                LocalDate.parse("2026-08-03"),
                1
        );

        assertEquals(1, result.imageUrls().size());
        assertTrue(result.imageUrl().endsWith("story_image.png"));
    }

    @Test
    void feedIncludesSessionWithOnlyEventImages() {
        when(store.findActiveOwnedDevices(10L))
                .thenReturn(List.of(ownedDevice(PAIRED_AT)));
        stubObjectsAt(
                UPLOADED_AT,
                key("2026-08-07", 1, "event_01.png"),
                key("2026-08-07", 1, "walk_log.md")
        );

        WalkDiaryService.DiaryFeed feed = service.getFeed(10L, null, 30);

        assertEquals(1, feed.items().size());
        assertEquals(LocalDate.parse("2026-08-07"), feed.items().getFirst().walkDate());
    }

    @Test
    void ignoresImagesInsideSubdirectories() {
        // flow_panels/ 는 진단용 부산물이라 일지 이미지로 세지 않는다.
        // 이걸 이미지로 인정하면 세션 폴더 최상위에 아무 이미지가 없어도
        // 완성된 일지처럼 보인다.
        when(store.findActiveOwnedDevice(10L, "device-001"))
                .thenReturn(java.util.Optional.of(ownedDevice(PAIRED_AT)));
        stubObjects(
                key("2026-08-07", 1, "flow_panels/event_01.png"),
                key("2026-08-07", 1, "walk_log.md")
        );

        BusinessException exception = assertThrows(
                BusinessException.class,
                () -> service.getDiary(
                        10L,
                        "device-001",
                        LocalDate.parse("2026-08-07"),
                        1
                )
        );

        assertEquals(ErrorCode.WALK_DIARY_NOT_FOUND, exception.errorCode());
    }

    @Test
    void returnsOwnedDiaryDirectlyFromFixedS3Path() {
        when(store.findActiveOwnedDevice(10L, "device-001"))
                .thenReturn(java.util.Optional.of(ownedDevice(PAIRED_AT)));

        WalkDiaryService.DiaryDetail result = service.getDiary(
                10L,
                "device-001",
                LocalDate.parse("2026-08-03"),
                1
        );

        assertEquals("device-001", result.deviceId());
        assertEquals(LocalDate.parse("2026-08-03"), result.walkDate());
        assertEquals(1, result.session());
        assertEquals("# 오늘의 산책", result.markdown());
        assertEquals("https://example.com/story.png", result.imageUrl());
        verify(s3Client).getObject(any(GetObjectRequest.class));
    }

    @Test
    void buildsDateFeedFromCompleteS3Sessions() {
        when(store.findActiveOwnedDevices(10L))
                .thenReturn(List.of(ownedDevice(PAIRED_AT)));
        stubObjects(
                key("2026-08-03", 2, "story_image.png"),
                key("2026-08-03", 2, "walk_log.md"),
                key("2026-08-03", 1, "story_image.png"),
                key("2026-08-03", 1, "walk_log.md"),
                key("2026-08-02", 1, "story_image.png"),
                key("2026-08-02", 1, "walk_log.md"),
                key("2026-08-01", 1, "story_image.png"),
                key("2026-08-01", 1, "walk_log.md"),
                key("2026-07-31", 1, "story_image.png")
        );

        WalkDiaryService.DiaryFeed feed = service.getFeed(10L, null, 2);

        assertEquals(2, feed.items().size());
        assertEquals(LocalDate.parse("2026-08-03"),
                feed.items().get(0).walkDate());
        assertEquals(2, feed.items().get(0).walkCount());
        assertEquals(1, feed.items().get(0).diaries().get(0).session());
        assertEquals(2, feed.items().get(0).diaries().get(1).session());
        assertEquals(LocalDate.parse("2026-08-02"), feed.nextCursor());
        assertTrue(feed.hasNext());
        ArgumentCaptor<ListObjectsV2Request> request =
                ArgumentCaptor.forClass(ListObjectsV2Request.class);
        verify(s3Client).listObjectsV2(request.capture());
        assertEquals("robot-images/device-001/", request.getValue().prefix());
    }

    @Test
    void appliesExclusiveDateCursorToS3Feed() {
        when(store.findActiveOwnedDevices(10L))
                .thenReturn(List.of(ownedDevice(PAIRED_AT)));
        stubObjects(
                key("2026-08-03", 1, "story_image.png"),
                key("2026-08-03", 1, "walk_log.md"),
                key("2026-08-02", 1, "story_image.png"),
                key("2026-08-02", 1, "walk_log.md")
        );

        WalkDiaryService.DiaryFeed feed = service.getFeed(
                10L,
                LocalDate.parse("2026-08-03"),
                30
        );

        assertEquals(1, feed.items().size());
        assertEquals(LocalDate.parse("2026-08-02"),
                feed.items().get(0).walkDate());
        assertFalse(feed.hasNext());
    }

    @Test
    void rejectsDiaryOfDeviceNotOwnedByUser() {
        when(store.findActiveOwnedDevice(10L, "device-001"))
                .thenReturn(java.util.Optional.empty());

        BusinessException exception = assertThrows(
                BusinessException.class,
                () -> service.getDiary(
                        10L,
                        "device-001",
                        LocalDate.parse("2026-08-03"),
                        1
                )
        );

        assertEquals(ErrorCode.WALK_DIARY_NOT_FOUND, exception.errorCode());
    }

    @Test
    void rejectsOversizedMarkdownFromGetMetadata() {
        when(store.findActiveOwnedDevice(10L, "device-001"))
                .thenReturn(java.util.Optional.of(ownedDevice(PAIRED_AT)));
        when(s3Client.getObject(any(GetObjectRequest.class)))
                .thenAnswer(ignored -> responseStream(new byte[0], 1025L));

        BusinessException exception = assertThrows(
                BusinessException.class,
                () -> service.getDiary(
                        10L,
                        "device-001",
                        LocalDate.parse("2026-08-03"),
                        1
                )
        );

        assertEquals(ErrorCode.WALK_DIARY_CONTENT_INVALID,
                exception.errorCode());
    }

    @Test
    void rejectsMalformedUtf8Markdown() {
        when(store.findActiveOwnedDevice(10L, "device-001"))
                .thenReturn(java.util.Optional.of(ownedDevice(PAIRED_AT)));
        when(s3Client.getObject(any(GetObjectRequest.class)))
                .thenAnswer(ignored -> responseStream(new byte[]{(byte) 0x80}));

        BusinessException exception = assertThrows(
                BusinessException.class,
                () -> service.getDiary(
                        10L,
                        "device-001",
                        LocalDate.parse("2026-08-03"),
                        1
                )
        );

        assertEquals(ErrorCode.WALK_DIARY_CONTENT_INVALID,
                exception.errorCode());
    }

    @Test
    void hidesObjectsUploadedBeforeCurrentPairing() {
        when(store.findActiveOwnedDevices(10L)).thenReturn(List.of(
                ownedDevice(Instant.parse("2026-08-05T00:00:00Z"))
        ));
        stubObjectsAt(
                UPLOADED_AT,
                key("2026-08-03", 1, "story_image.png"),
                key("2026-08-03", 1, "walk_log.md")
        );

        WalkDiaryService.DiaryFeed feed = service.getFeed(10L, null, 30);

        assertTrue(feed.items().isEmpty());
    }

    @Test
    void rejectsDetailWhenImageIsMissing() {
        when(store.findActiveOwnedDevice(10L, "device-001"))
                .thenReturn(java.util.Optional.of(ownedDevice(PAIRED_AT)));
        stubObjects(key("2026-08-03", 1, "walk_log.md"));

        BusinessException exception = assertThrows(
                BusinessException.class,
                () -> service.getDiary(
                        10L,
                        "device-001",
                        LocalDate.parse("2026-08-03"),
                        1
                )
        );

        assertEquals(ErrorCode.WALK_DIARY_NOT_FOUND, exception.errorCode());
        verify(s3Client, never()).getObject(any(GetObjectRequest.class));
    }

    @Test
    void readsEveryS3ListingPage() {
        when(store.findActiveOwnedDevices(10L))
                .thenReturn(List.of(ownedDevice(PAIRED_AT)));
        when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                .thenReturn(
                        page(true, "next", object(
                                key("2026-08-03", 1, "story_image.png"),
                                UPLOADED_AT
                        )),
                        page(false, null, object(
                                key("2026-08-03", 1, "walk_log.md"),
                                UPLOADED_AT
                        ))
                );

        WalkDiaryService.DiaryFeed feed = service.getFeed(10L, null, 30);

        assertEquals(1, feed.items().size());
        verify(s3Client, times(2)).listObjectsV2(
                any(ListObjectsV2Request.class)
        );
    }

    @Test
    void mapsS3ListFailureToStorageUnavailable() {
        when(store.findActiveOwnedDevices(10L))
                .thenReturn(List.of(ownedDevice(PAIRED_AT)));
        when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                .thenThrow(S3Exception.builder()
                        .statusCode(403)
                        .message("Access denied")
                        .build());

        BusinessException exception = assertThrows(
                BusinessException.class,
                () -> service.getFeed(10L, null, 30)
        );

        assertEquals(ErrorCode.WALK_DIARY_STORAGE_UNAVAILABLE,
                exception.errorCode());
    }

    private void stubObjects(String... keys) {
        stubObjectsAt(UPLOADED_AT, keys);
    }

    private void stubObjectsAt(Instant uploadedAt, String... keys) {
        List<software.amazon.awssdk.services.s3.model.S3Object> objects =
                java.util.Arrays.stream(keys)
                        .map(key -> object(key, uploadedAt))
                        .toList();
        when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                .thenReturn(page(false, null, objects.toArray(
                        software.amazon.awssdk.services.s3.model.S3Object[]::new
                )));
    }

    private ListObjectsV2Response page(
            boolean truncated,
            String nextToken,
            software.amazon.awssdk.services.s3.model.S3Object... objects
    ) {
        return ListObjectsV2Response.builder()
                .contents(objects)
                .isTruncated(truncated)
                .nextContinuationToken(nextToken)
                .build();
    }

    private software.amazon.awssdk.services.s3.model.S3Object object(
            String key,
            Instant uploadedAt
    ) {
        return software.amazon.awssdk.services.s3.model.S3Object.builder()
                .key(key)
                .lastModified(uploadedAt)
                .build();
    }

    private WalkDiaryStore.OwnedDevice ownedDevice(Instant pairedAt) {
        return new WalkDiaryStore.OwnedDevice("device-001", pairedAt);
    }

    private String key(String date, int session, String file) {
        return "robot-images/device-001/" + date + "/session"
                + session + "/" + file;
    }

    private ResponseInputStream<GetObjectResponse> responseStream(
            byte[] content
    ) {
        return responseStream(content, content.length);
    }

    private ResponseInputStream<GetObjectResponse> responseStream(
            byte[] content,
            long declaredLength
    ) {
        return new ResponseInputStream<>(
                GetObjectResponse.builder()
                        .contentLength(declaredLength)
                        .build(),
                AbortableInputStream.create(new ByteArrayInputStream(content))
        );
    }
}
