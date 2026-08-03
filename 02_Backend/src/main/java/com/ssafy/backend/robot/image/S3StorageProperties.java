package com.ssafy.backend.robot.image;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "storage.s3")
public record S3StorageProperties(
        boolean enabled,
        String bucket,
        String region,
        long presignDurationSeconds,
        long maxFileSizeBytes
) {
}
