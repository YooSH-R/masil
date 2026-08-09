package com.ssafy.backend.robot.mqtt;

import java.time.Instant;
import java.util.UUID;

public record AffectionChangedMessage(
        UUID messageId,
        String messageVersion,
        String deviceId,
        UUID eventMessageId,
        int previousScore,
        int scoreChange,
        int currentScore,
        int affinityLevel,
        String mood,
        Instant occurredAt
) {
}
