package com.ssafy.backend.robot.image;

import com.ssafy.backend.robot.image.RobotImageController.ImageResponse;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

@Service
@ConditionalOnProperty(name = "storage.s3.enabled", havingValue = "true")
class RobotImagePersistenceService {

    private final RobotImageStore store;

    RobotImagePersistenceService(RobotImageStore store) {
        this.store = store;
    }

    @Transactional(readOnly = true)
    long requireRobotId(String deviceId) {
        return store.requireRobotId(deviceId);
    }

    @Transactional
    void createPending(
            UUID imageId,
            long robotId,
            String objectKey,
            String contentType,
            long fileSize,
            Instant capturedAt,
            Instant expiresAt
    ) {
        store.createPending(
                imageId,
                robotId,
                objectKey,
                contentType,
                fileSize,
                capturedAt,
                expiresAt
        );
    }

    @Transactional(readOnly = true)
    RobotImageStore.StoredImage requirePending(
            String deviceId,
            UUID imageId
    ) {
        return store.requirePending(deviceId, imageId);
    }

    @Transactional
    ImageResponse completeUpload(
            String deviceId,
            UUID imageId,
            long actualSize,
            String actualContentType,
            Instant uploadedAt
    ) {
        RobotImageStore.StoredImage image =
                store.requirePending(deviceId, imageId);
        validateMetadata(image, actualSize, actualContentType);
        store.markUploaded(imageId, actualSize, uploadedAt);
        return image.toResponse(actualSize, uploadedAt);
    }

    @Transactional(readOnly = true)
    List<ImageResponse> listImages(Long userId, Long petId) {
        store.requirePetOwnership(userId, petId);
        return store.findUploadedByPetId(petId);
    }

    @Transactional(readOnly = true)
    RobotImageStore.StoredImage requireUploaded(
            Long userId,
            UUID imageId
    ) {
        return store.requireUploaded(userId, imageId);
    }

    private void validateMetadata(
            RobotImageStore.StoredImage image,
            long actualSize,
            String actualContentType
    ) {
        if (actualSize != image.expectedSize()
                || !image.contentType().equalsIgnoreCase(actualContentType)) {
            throw new IllegalArgumentException(
                    "업로드된 이미지 정보가 요청과 다릅니다."
            );
        }
    }
}
