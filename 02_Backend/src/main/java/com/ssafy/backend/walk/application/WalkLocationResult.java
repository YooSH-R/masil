package com.ssafy.backend.walk.application;

import java.math.BigDecimal;
import java.time.Instant;

public record WalkLocationResult(
        BigDecimal latitude,
        BigDecimal longitude,
        BigDecimal accuracy,
        Integer sequence,
        Instant recordedAt
) {
}
