package com.ssafy.backend.robot.application;

import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

@Component
public class RobotPairingRateLimiter {

    private static final long CLEANUP_INTERVAL_MASK = 255L;

    private final ConcurrentMap<Long, AttemptWindow> attemptsByUser =
            new ConcurrentHashMap<>();
    private final AtomicLong requestCount = new AtomicLong();
    private final int maxAttempts;
    private final Duration windowDuration;
    private final Clock clock;

    public RobotPairingRateLimiter(
            @Value("${robot.pairing.rate-limit.max-attempts:10}") int maxAttempts,
            @Value("${robot.pairing.rate-limit.window:1m}") Duration windowDuration,
            Clock clock
    ) {
        if (maxAttempts < 1) {
            throw new IllegalArgumentException("로봇 등록 요청 제한은 1 이상이어야 합니다.");
        }
        if (windowDuration.isNegative() || windowDuration.isZero()) {
            throw new IllegalArgumentException("로봇 등록 요청 제한 시간은 양수여야 합니다.");
        }
        this.maxAttempts = maxAttempts;
        this.windowDuration = windowDuration;
        this.clock = clock;
    }

    public void checkAllowed(Long userId) {
        Instant now = clock.instant();
        AtomicBoolean allowed = new AtomicBoolean(true);

        attemptsByUser.compute(userId, (ignored, current) -> {
            if (current == null || !now.isBefore(current.expiresAt())) {
                return new AttemptWindow(1, now.plus(windowDuration));
            }
            if (current.attempts() >= maxAttempts) {
                allowed.set(false);
                return current;
            }
            return new AttemptWindow(current.attempts() + 1, current.expiresAt());
        });

        if ((requestCount.incrementAndGet() & CLEANUP_INTERVAL_MASK) == 0) {
            attemptsByUser.entrySet().removeIf(
                    entry -> !now.isBefore(entry.getValue().expiresAt())
            );
        }

        if (!allowed.get()) {
            throw new BusinessException(ErrorCode.RATE_LIMIT_EXCEEDED);
        }
    }

    private record AttemptWindow(int attempts, Instant expiresAt) {
    }
}
