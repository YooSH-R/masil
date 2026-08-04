package com.ssafy.backend.walk.diary;

import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.http.AbortableInputStream;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.PresignedGetObjectRequest;

import java.io.ByteArrayInputStream;
import java.net.URL;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class WalkDiaryServiceTest {

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
                        1024,
                        2,
                        5
                )
        );

        byte[] markdown = "# 오늘의 산책".getBytes(java.nio.charset.StandardCharsets.UTF_8);
        when(s3Client.getObject(any(GetObjectRequest.class)))
                .thenAnswer(ignored -> responseStream(markdown));
        PresignedGetObjectRequest signed =
                mock(PresignedGetObjectRequest.class);
        when(signed.url()).thenReturn(new URL("https://example.com/story.png"));
        when(presigner.presignGetObject(any(
                software.amazon.awssdk.services.s3.presigner.model
                        .GetObjectPresignRequest.class
        ))).thenReturn(signed);
    }

    @Test
    void returnsOwnedDiaryFromS3() {
        when(store.findOwnedDiary(10L, 20L)).thenReturn(Optional.of(
                diary(20L, LocalDate.parse("2026-08-03"), 1)
        ));

        WalkDiaryService.DiaryDetail result = service.getDiary(10L, 20L);

        assertEquals(20L, result.walkId());
        assertEquals(1, result.session());
        assertEquals("# 오늘의 산책", result.markdown());
        assertEquals("https://example.com/story.png", result.imageUrl());
        verify(s3Client).getObject(any(GetObjectRequest.class));
    }

    @Test
    void groupsFeedByDateAndKeepsSessionOrder() {
        when(store.findOwnedDiaryFeed(10L, null, 3)).thenReturn(List.of(
                feedRow(21L, LocalDate.parse("2026-08-03"), 1),
                feedRow(22L, LocalDate.parse("2026-08-03"), 2),
                feedRow(19L, LocalDate.parse("2026-08-02"), 1),
                feedRow(18L, LocalDate.parse("2026-08-01"), 1)
        ));

        WalkDiaryService.DiaryFeed feed = service.getFeed(10L, null, 2);

        assertEquals(2, feed.items().size());
        assertEquals(
                LocalDate.parse("2026-08-03"),
                feed.items().get(0).walkDate()
        );
        assertEquals(2, feed.items().get(0).walkCount());
        assertEquals(22L, feed.items().get(0).walks().get(1).walkId());
        assertEquals(LocalDate.parse("2026-08-02"), feed.nextCursor());
        assertTrue(feed.hasNext());
    }

    @Test
    void rejectsDiaryOwnedByAnotherUser() {
        when(store.findOwnedDiary(10L, 20L)).thenReturn(Optional.empty());

        BusinessException exception = assertThrows(
                BusinessException.class,
                () -> service.getDiary(10L, 20L)
        );
        assertEquals(ErrorCode.WALK_DIARY_NOT_FOUND, exception.errorCode());
    }

    @Test
    void rejectsOversizedMarkdownFromGetMetadata() {
        when(store.findOwnedDiary(10L, 20L)).thenReturn(Optional.of(
                diary(20L, LocalDate.parse("2026-08-03"), 1)
        ));
        when(s3Client.getObject(any(GetObjectRequest.class)))
                .thenAnswer(ignored -> responseStream(new byte[0], 1025L));

        BusinessException exception = assertThrows(
                BusinessException.class,
                () -> service.getDiary(10L, 20L)
        );

        assertEquals(
                ErrorCode.WALK_DIARY_CONTENT_INVALID,
                exception.errorCode()
        );
    }

    @Test
    void rejectsMalformedUtf8Markdown() {
        when(store.findOwnedDiary(10L, 20L)).thenReturn(Optional.of(
                diary(20L, LocalDate.parse("2026-08-03"), 1)
        ));
        when(s3Client.getObject(any(GetObjectRequest.class)))
                .thenAnswer(ignored -> responseStream(new byte[]{(byte) 0x80}));

        BusinessException exception = assertThrows(
                BusinessException.class,
                () -> service.getDiary(10L, 20L)
        );

        assertEquals(
                ErrorCode.WALK_DIARY_CONTENT_INVALID,
                exception.errorCode()
        );
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

    private WalkDiaryStore.StoredDiary diary(
            long walkId,
            LocalDate date,
            int session
    ) {
        return new WalkDiaryStore.StoredDiary(
                walkId,
                "device-001",
                date,
                session,
                "robot-images/device-001/" + date + "/session"
                        + session + "/",
                Instant.parse(date + "T04:30:00Z"),
                Instant.parse(date + "T05:00:00Z")
        );
    }

    private WalkDiaryStore.FeedRow feedRow(
            long walkId,
            LocalDate date,
            int session
    ) {
        return new WalkDiaryStore.FeedRow(
                walkId,
                date,
                session,
                Instant.parse(date + "T04:30:00Z"),
                Instant.parse(date + "T05:00:00Z")
        );
    }
}
