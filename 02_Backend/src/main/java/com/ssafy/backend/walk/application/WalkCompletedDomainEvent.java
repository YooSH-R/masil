package com.ssafy.backend.walk.application;

import java.time.Instant;

public record WalkCompletedDomainEvent(
        Long walkId,
        Long robotId,
        Long petId,
        String deviceId,
        Instant occurredAt,
        int durationSeconds,
        int distanceMeters
) {
}
