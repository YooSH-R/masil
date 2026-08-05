package com.ssafy.backend.walk.application;

import com.ssafy.backend.walk.infrastructure.persistence.WalkLocationBatchRequestStore;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;

@Component
@ConditionalOnProperty(
        name = "walk.location-batch-request-cleanup-scheduler-enabled",
        havingValue = "true",
        matchIfMissing = true
)
public class WalkLocationBatchRequestCleanupScheduler {

    private final WalkLocationBatchRequestStore batchRequestStore;
    private final Clock clock;
    private final Duration retention;
    private final int batchSize;

    public WalkLocationBatchRequestCleanupScheduler(
            WalkLocationBatchRequestStore batchRequestStore,
            Clock clock,
            @Value("${walk.location-batch-request-retention-seconds:2592000}")
            long retentionSeconds,
            @Value("${walk.location-batch-request-cleanup-batch-size:1000}")
            int batchSize
    ) {
        if (retentionSeconds <= 0) {
            throw new IllegalArgumentException(
                    "walk.location-batch-request-retention-seconds must be positive"
            );
        }
        if (batchSize <= 0) {
            throw new IllegalArgumentException(
                    "walk.location-batch-request-cleanup-batch-size must be positive"
            );
        }
        this.batchRequestStore = batchRequestStore;
        this.clock = clock;
        this.retention = Duration.ofSeconds(retentionSeconds);
        this.batchSize = batchSize;
    }

    @Scheduled(
            fixedDelayString =
                    "${walk.location-batch-request-cleanup-delay-ms:3600000}"
    )
    @Transactional
    public int deleteExpiredBatchRequests() {
        Instant cutoff = clock.instant().minus(retention);
        return batchRequestStore.deleteCreatedBefore(cutoff, batchSize);
    }
}
