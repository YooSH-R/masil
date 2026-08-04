package com.ssafy.backend.robot.image;

import com.ssafy.backend.auth.security.UserPrincipal;
import com.ssafy.backend.common.api.ApiResponse;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

@Validated
@RestController
@RequestMapping("/v1")
@ConditionalOnProperty(name = "storage.s3.enabled", havingValue = "true")
public class RobotImageController {

    private final RobotImageService robotImageService;

    public RobotImageController(RobotImageService robotImageService) {
        this.robotImageService = robotImageService;
    }

    @PostMapping("/devices/{deviceId}/images/presigned-url")
    public ApiResponse<UploadUrlResponse> createUploadUrl(
            @PathVariable String deviceId,
            @Valid @RequestBody UploadUrlRequest request
    ) {
        return ApiResponse.success(robotImageService.createUploadUrl(
                deviceId,
                request
        ));
    }

    @PostMapping("/devices/{deviceId}/images/{imageId}/complete")
    public ApiResponse<ImageResponse> completeUpload(
            @PathVariable String deviceId,
            @PathVariable UUID imageId
    ) {
        return ApiResponse.success(robotImageService.completeUpload(
                deviceId,
                imageId
        ));
    }

    @GetMapping("/pets/{petId}/images")
    public ApiResponse<List<ImageResponse>> listImages(
            @PathVariable Long petId,
            @AuthenticationPrincipal UserPrincipal principal
    ) {
        return ApiResponse.success(robotImageService.listImages(
                principal.userId(),
                petId
        ));
    }

    @GetMapping("/images/{imageId}/download-url")
    public ApiResponse<DownloadUrlResponse> createDownloadUrl(
            @PathVariable UUID imageId,
            @AuthenticationPrincipal UserPrincipal principal
    ) {
        return ApiResponse.success(robotImageService.createDownloadUrl(
                principal.userId(),
                imageId
        ));
    }

    public record UploadUrlRequest(
            @NotBlank String contentType,
            @Positive long fileSize,
            @NotNull Instant capturedAt
    ) {
    }

    public record UploadUrlResponse(
            UUID imageId,
            String objectKey,
            String uploadUrl,
            Instant expiresAt
    ) {
    }

    public record ImageResponse(
            UUID imageId,
            String deviceId,
            String objectKey,
            String contentType,
            Long fileSize,
            Instant capturedAt,
            Instant uploadedAt
    ) {
    }

    public record DownloadUrlResponse(
            UUID imageId,
            String downloadUrl,
            Instant expiresAt
    ) {
    }
}
