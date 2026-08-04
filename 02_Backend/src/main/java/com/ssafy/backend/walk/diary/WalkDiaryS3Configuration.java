package com.ssafy.backend.walk.diary;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.core.client.config.ClientOverrideConfiguration;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;

import java.time.Duration;

@Configuration
@EnableConfigurationProperties(WalkDiaryS3Properties.class)
@ConditionalOnProperty(name = "storage.s3.enabled", havingValue = "true")
public class WalkDiaryS3Configuration {

    @Bean
    S3Client s3Client(WalkDiaryS3Properties properties) {
        ClientOverrideConfiguration overrideConfiguration =
                ClientOverrideConfiguration.builder()
                        .apiCallAttemptTimeout(Duration.ofSeconds(
                                properties.apiCallAttemptTimeoutSeconds()
                        ))
                        .apiCallTimeout(Duration.ofSeconds(
                                properties.apiCallTimeoutSeconds()
                        ))
                        .build();
        return S3Client.builder()
                .region(Region.of(properties.region()))
                .credentialsProvider(DefaultCredentialsProvider.create())
                .overrideConfiguration(overrideConfiguration)
                .build();
    }

    @Bean
    S3Presigner s3Presigner(WalkDiaryS3Properties properties) {
        return S3Presigner.builder()
                .region(Region.of(properties.region()))
                .credentialsProvider(DefaultCredentialsProvider.create())
                .build();
    }
}
