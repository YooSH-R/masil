package com.ssafy.backend.robot.image;

import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class RobotImagePersistenceServiceTest {

    @Test
    void revalidatesPendingImageBeforeCompletingUpload() {
        RobotImageStore store = mock(RobotImageStore.class);
        RobotImagePersistenceService service =
                new RobotImagePersistenceService(store);
        UUID imageId = UUID.randomUUID();
        RobotImageStore.StoredImage image = storedImage(imageId);
        when(store.requirePending("device-001", imageId)).thenReturn(image);
        Instant uploadedAt = Instant.parse("2026-07-31T00:01:00Z");

        var response = service.completeUpload(
                "device-001",
                imageId,
                1024L,
                "image/png",
                uploadedAt
        );

        assertEquals(imageId, response.imageId());
        verify(store).markUploaded(imageId, 1024L, uploadedAt);
    }

    @Test
    void doesNotCompleteWhenMetadataChangedBeforeFinalTransaction() {
        RobotImageStore store = mock(RobotImageStore.class);
        RobotImagePersistenceService service =
                new RobotImagePersistenceService(store);
        UUID imageId = UUID.randomUUID();
        when(store.requirePending("device-001", imageId)).thenReturn(
                storedImage(imageId)
        );

        assertThrows(
                IllegalArgumentException.class,
                () -> service.completeUpload(
                        "device-001",
                        imageId,
                        512L,
                        "image/png",
                        Instant.parse("2026-07-31T00:01:00Z")
                )
        );
        verify(store, never()).markUploaded(
                any(UUID.class),
                org.mockito.ArgumentMatchers.anyLong(),
                any(Instant.class)
        );
    }

    private RobotImageStore.StoredImage storedImage(UUID imageId) {
        return new RobotImageStore.StoredImage(
                imageId,
                "device-001",
                "robot-images/device-001/test.png",
                "image/png",
                1024L,
                Instant.parse("2026-07-31T00:00:00Z"),
                null
        );
    }
}
