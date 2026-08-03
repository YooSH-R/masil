package com.ssafy.backend.robot.mqtt;

import java.time.Instant;
import java.util.UUID;

public record BehaviorRequestMessage(
        UUID requestId,
        String messageVersion,
        String deviceId,
        BehaviorRequestType requestType,
        String message,
        Instant createdAt,
        Instant expiresAt
) {
}
