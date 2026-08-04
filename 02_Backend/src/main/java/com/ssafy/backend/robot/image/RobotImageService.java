package com.ssafy.backend.robot.image;

import com.ssafy.backend.robot.image.RobotImageController.DownloadUrlResponse;
import com.ssafy.backend.robot.image.RobotImageController.ImageResponse;
import com.ssafy.backend.robot.image.RobotImageController.UploadUrlRequest;
import com.ssafy.backend.robot.image.RobotImageController.UploadUrlResponse;
import com.ssafy.backend.walk.diary.WalkDiaryS3Properties;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.HeadObjectRequest;
import software.amazon.awssdk.services.s3.model.HeadObjectResponse;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;
import software.amazon.awssdk.services.s3.presigner.model.PutObjectPresignRequest;

import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Set;
import java.util.UUID;

@Service
@ConditionalOnProperty(name = "storage.s3.enabled", havingValue = "true")
public class RobotImageService {

    private static final Set<String> ALLOWED_TYPES = Set.of(
            "image/jpeg",
            "image/png",
            "image/webp"
    );
    private static final DateTimeFormatter KEY_DATE =
            DateTimeFormatter.ofPattern("yyyy/MM").withZone(ZoneOffset.UTC);

    private final RobotImagePersistenceService persistenceService;
    private final S3Client s3Client;
    private final S3Presigner presigner;
    private final WalkDiaryS3Properties properties;

    public RobotImageService(
            RobotImagePersistenceService persistenceService,
            S3Client s3Client,
            S3Presigner presigner,
            WalkDiaryS3Properties properties
    ) {
        this.persistenceService = persistenceService;
        this.s3Client = s3Client;
        this.presigner = presigner;
        this.properties = properties;
    }

    public UploadUrlResponse createUploadUrl(
            String deviceId,
            UploadUrlRequest request
    ) {
        validateUpload(request);
        long robotId = persistenceService.requireRobotId(deviceId);
        UUID imageId = UUID.randomUUID();
        Instant expiresAt = Instant.now().plusSeconds(
                properties.presignDurationSeconds()
        );
        String objectKey = "robot-images/" + deviceId + "/"
                + KEY_DATE.format(request.capturedAt()) + "/"
                + imageId + extensionOf(request.contentType());

        PutObjectRequest putObject = PutObjectRequest.builder()
                .bucket(properties.bucket())
                .key(objectKey)
                .contentType(request.contentType())
                .contentLength(request.fileSize())
                .build();
        String uploadUrl = presigner.presignPutObject(
                PutObjectPresignRequest.builder()
                        .signatureDuration(Duration.ofSeconds(
                                properties.presignDurationSeconds()
                        ))
                        .putObjectRequest(putObject)
                        .build()
        ).url().toString();

        persistenceService.createPending(
                imageId,
                robotId,
                objectKey,
                request.contentType(),
                request.fileSize(),
                request.capturedAt(),
                expiresAt
        );
        return new UploadUrlResponse(imageId, objectKey, uploadUrl, expiresAt);
    }

    public ImageResponse completeUpload(String deviceId, UUID imageId) {
        RobotImageStore.StoredImage image =
                persistenceService.requirePending(deviceId, imageId);
        HeadObjectResponse head = s3Client.headObject(
                HeadObjectRequest.builder()
                        .bucket(properties.bucket())
                        .key(image.objectKey())
                        .build()
        );
        validateMetadata(image, head);
        return persistenceService.completeUpload(
                deviceId,
                imageId,
                head.contentLength(),
                head.contentType(),
                Instant.now()
        );
    }

    public List<ImageResponse> listImages(Long userId, Long petId) {
        return persistenceService.listImages(userId, petId);
    }

    public DownloadUrlResponse createDownloadUrl(Long userId, UUID imageId) {
        RobotImageStore.StoredImage image =
                persistenceService.requireUploaded(userId, imageId);
        Instant expiresAt = Instant.now().plusSeconds(
                properties.presignDurationSeconds()
        );
        GetObjectRequest getObject = GetObjectRequest.builder()
                .bucket(properties.bucket())
                .key(image.objectKey())
                .build();
        String url = presigner.presignGetObject(
                GetObjectPresignRequest.builder()
                        .signatureDuration(Duration.ofSeconds(
                                properties.presignDurationSeconds()
                        ))
                        .getObjectRequest(getObject)
                        .build()
        ).url().toString();
        return new DownloadUrlResponse(imageId, url, expiresAt);
    }

    private void validateMetadata(
            RobotImageStore.StoredImage image,
            HeadObjectResponse head
    ) {
        if (head.contentLength() != image.expectedSize()
                || !image.contentType().equalsIgnoreCase(head.contentType())) {
            throw new IllegalArgumentException(
                    "업로드된 이미지 정보가 요청과 다릅니다."
            );
        }
    }

    private void validateUpload(UploadUrlRequest request) {
        if (!ALLOWED_TYPES.contains(request.contentType())) {
            throw new IllegalArgumentException("지원하지 않는 이미지 형식입니다.");
        }
        if (request.fileSize() > properties.maxFileSizeBytes()) {
            throw new IllegalArgumentException("이미지 크기 제한을 초과했습니다.");
        }
    }

    private String extensionOf(String contentType) {
        return switch (contentType) {
            case "image/jpeg" -> ".jpg";
            case "image/png" -> ".png";
            case "image/webp" -> ".webp";
            default -> throw new IllegalArgumentException(
                    "지원하지 않는 이미지 형식입니다."
            );
        };
    }
}
