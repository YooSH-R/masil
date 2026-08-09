package com.ssafy.backend.robot.image;

import com.ssafy.backend.robot.image.RobotImageController.ImageResponse;
import com.ssafy.backend.robot.image.RobotImageController.UploadUrlRequest;
import com.ssafy.backend.walk.diary.WalkDiaryS3Properties;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.HeadObjectRequest;
import software.amazon.awssdk.services.s3.model.HeadObjectResponse;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;

import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class RobotImageServiceTest {

    private RobotImagePersistenceService persistenceService;
    private S3Client s3Client;
    private RobotImageService service;

    @BeforeEach
    void setUp() {
        persistenceService = mock(RobotImagePersistenceService.class);
        s3Client = mock(S3Client.class);
        service = new RobotImageService(
                persistenceService,
                s3Client,
                mock(S3Presigner.class),
                new WalkDiaryS3Properties(
                        true,
                        "test-bucket",
                        "ap-northeast-2",
                        300,
                        10_485_760,
                        1_048_576,
                        2,
                        5
                )
        );
    }

    @Test
    void rejectsOversizedUploadBeforeDatabaseOrS3Access() {
        UploadUrlRequest request = new UploadUrlRequest(
                "image/jpeg",
                10_485_761,
                Instant.parse("2026-08-04T00:00:00Z")
        );

        assertThrows(
                IllegalArgumentException.class,
                () -> service.createUploadUrl("device-001", request)
        );
        verifyNoInteractions(persistenceService, s3Client);
    }

    @Test
    void verifiesS3MetadataBeforeCompletingDatabaseState() {
        UUID imageId = UUID.randomUUID();
        Instant capturedAt = Instant.parse("2026-08-04T00:00:00Z");
        RobotImageStore.StoredImage stored = new RobotImageStore.StoredImage(
                imageId,
                "device-001",
                "robot-images/device-001/photo.jpg",
                "image/jpeg",
                2048,
                capturedAt,
                null
        );
        ImageResponse completed = new ImageResponse(
                imageId,
                "device-001",
                stored.objectKey(),
                stored.contentType(),
                2048L,
                capturedAt,
                capturedAt.plusSeconds(30)
        );
        when(persistenceService.requirePending("device-001", imageId))
                .thenReturn(stored);
        when(s3Client.headObject(any(HeadObjectRequest.class)))
                .thenReturn(HeadObjectResponse.builder()
                        .contentLength(2048L)
                        .contentType("image/jpeg")
                        .build());
        when(persistenceService.completeUpload(
                eq("device-001"),
                eq(imageId),
                eq(2048L),
                eq("image/jpeg"),
                any(Instant.class)
        )).thenReturn(completed);

        ImageResponse response = service.completeUpload(
                "device-001",
                imageId
        );

        assertEquals(imageId, response.imageId());
        verify(s3Client).headObject(any(HeadObjectRequest.class));
        verify(persistenceService).completeUpload(
                eq("device-001"),
                eq(imageId),
                eq(2048L),
                eq("image/jpeg"),
                any(Instant.class)
        );
    }
}
