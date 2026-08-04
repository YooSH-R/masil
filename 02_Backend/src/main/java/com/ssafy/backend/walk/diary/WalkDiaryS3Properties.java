package com.ssafy.backend.walk.diary;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Positive;

@Validated
@ConfigurationProperties(prefix = "storage.s3")
public record WalkDiaryS3Properties(
        boolean enabled,
        @NotBlank String bucket,
        @NotBlank String region,
        @Positive long presignDurationSeconds,
        @Positive @Max(10_485_760) long maxFileSizeBytes,
        @Positive @Max(10_485_760) long maxMarkdownBytes,
        @Positive @Max(30) long apiCallAttemptTimeoutSeconds,
        @Positive @Max(60) long apiCallTimeoutSeconds
) {
    public WalkDiaryS3Properties {
        if (apiCallTimeoutSeconds < apiCallAttemptTimeoutSeconds) {
            throw new IllegalArgumentException(
                    "S3 전체 제한시간은 시도별 제한시간보다 짧을 수 없습니다."
            );
        }
    }
}
