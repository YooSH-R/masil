package com.ssafy.backend.robot.image;

import com.ssafy.backend.robot.image.RobotImageController.UploadUrlRequest;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.HeadObjectRequest;
import software.amazon.awssdk.services.s3.model.HeadObjectResponse;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;

import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class RobotImageServiceTest {

    private RobotImageStore store;
    private S3Client s3Client;
    private RobotImageService service;

    @BeforeEach
    void setUp() {
        store = mock(RobotImageStore.class);
        s3Client = mock(S3Client.class);
        S3Presigner presigner = mock(S3Presigner.class);
        S3StorageProperties properties = new S3StorageProperties(
                true,
                "test-bucket",
                "ap-northeast-2",
                300,
                10 * 1024 * 1024
        );
        service = new RobotImageService(
                store,
                s3Client,
                presigner,
                properties
        );
    }

    @Test
    void completesUploadWhenS3MetadataMatchesPendingImage() {
        UUID imageId = UUID.randomUUID();
        Instant capturedAt = Instant.parse("2026-07-30T00:00:00Z");
        RobotImageStore.StoredImage image = new RobotImageStore.StoredImage(
                imageId,
                "device-001",
                "robot-images/device-001/test.png",
                "image/png",
                1024,
                capturedAt,
                null
        );
        when(store.requirePending("device-001", imageId)).thenReturn(image);
        when(s3Client.headObject(any(HeadObjectRequest.class))).thenReturn(
                HeadObjectResponse.builder()
                        .contentLength(1024L)
                        .contentType("image/png")
                        .build()
        );

        var response = service.completeUpload("device-001", imageId);

        assertEquals(imageId, response.imageId());
        assertEquals(1024L, response.fileSize());
        assertEquals("image/png", response.contentType());
        assertNotNull(response.uploadedAt());
        verify(store).markUploaded(
                org.mockito.ArgumentMatchers.eq(imageId),
                org.mockito.ArgumentMatchers.eq(1024L),
                any(Instant.class)
        );
    }

    @Test
    void rejectsUploadWhenS3FileSizeDiffersFromRequest() {
        UUID imageId = UUID.randomUUID();
        RobotImageStore.StoredImage image = new RobotImageStore.StoredImage(
                imageId,
                "device-001",
                "robot-images/device-001/test.png",
                "image/png",
                1024,
                Instant.parse("2026-07-30T00:00:00Z"),
                null
        );
        when(store.requirePending("device-001", imageId)).thenReturn(image);
        when(s3Client.headObject(any(HeadObjectRequest.class))).thenReturn(
                HeadObjectResponse.builder()
                        .contentLength(512L)
                        .contentType("image/png")
                        .build()
        );

        assertThrows(
                IllegalArgumentException.class,
                () -> service.completeUpload("device-001", imageId)
        );
        verify(store, never()).markUploaded(
                any(UUID.class),
                org.mockito.ArgumentMatchers.anyLong(),
                any(Instant.class)
        );
    }

    @Test
    void rejectsUnsupportedImageContentTypeBeforeAccessingStorage() {
        UploadUrlRequest request = new UploadUrlRequest(
                "image/gif",
                1024,
                Instant.parse("2026-07-30T00:00:00Z")
        );

        assertThrows(
                IllegalArgumentException.class,
                () -> service.createUploadUrl("device-001", request)
        );
        verify(store, never()).requireRobotId(any(String.class));
    }

    @Test
    void rejectsImageLargerThanConfiguredLimit() {
        UploadUrlRequest request = new UploadUrlRequest(
                "image/png",
                10 * 1024 * 1024 + 1L,
                Instant.parse("2026-07-30T00:00:00Z")
        );

        assertThrows(
                IllegalArgumentException.class,
                () -> service.createUploadUrl("device-001", request)
        );
        verify(store, never()).requireRobotId(any(String.class));
    }
}
