package com.ssafy.backend.robot.application;

import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class RobotPairingRateLimiterTest {

    @Test
    void rejectsAttemptsBeyondConfiguredLimitPerUser() {
        RobotPairingRateLimiter limiter = new RobotPairingRateLimiter(
                2,
                Duration.ofMinutes(1),
                Clock.fixed(
                        Instant.parse("2026-07-29T03:15:00Z"),
                        ZoneOffset.UTC
                )
        );

        assertDoesNotThrow(() -> limiter.checkAllowed(1L));
        assertDoesNotThrow(() -> limiter.checkAllowed(1L));

        BusinessException exception = assertThrows(
                BusinessException.class,
                () -> limiter.checkAllowed(1L)
        );

        assertEquals(ErrorCode.RATE_LIMIT_EXCEEDED, exception.errorCode());
        assertDoesNotThrow(() -> limiter.checkAllowed(2L));
    }
}
