package com.ssafy.backend.walk.application;

import java.time.Instant;
import java.util.List;

public record WalkSummaryResult(
        Long walkId,
        Integer durationSeconds,
        Integer distanceMeters,
        List<WalkLocationResult> route,
        Instant startedAt,
        Instant endedAt
) {
}
