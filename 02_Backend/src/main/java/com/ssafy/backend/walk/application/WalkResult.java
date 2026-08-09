package com.ssafy.backend.walk.application;

import com.ssafy.backend.walk.domain.WalkStatus;
import com.ssafy.backend.walk.infrastructure.persistence.WalkJpaEntity;

import java.math.RoundingMode;
import java.time.Instant;

public record WalkResult(
        Long walkId,
        WalkStatus status,
        Instant createdAt,
        Instant startedAt,
        Instant endedAt,
        Integer durationSeconds,
        Integer distanceMeters
) {
    public static WalkResult from(WalkJpaEntity walk) {
        Integer roundedDistance = walk.getDistanceMeters() == null
                ? null
                : walk.getDistanceMeters()
                        .setScale(0, RoundingMode.HALF_UP)
                        .intValue();
        return new WalkResult(
                walk.getId(),
                walk.getStatus(),
                walk.getCreatedAt(),
                walk.getStartedAt(),
                walk.getEndedAt(),
                walk.getDurationSeconds(),
                roundedDistance
        );
    }
}
