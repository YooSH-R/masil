package com.ssafy.backend.robot.mqtt;

import tools.jackson.databind.JsonNode;

import java.time.Instant;
import java.util.UUID;

public record RobotRequestResultMessage(
        UUID messageId,
        String messageVersion,
        String deviceId,
        UUID requestId,
        BehaviorRequestStatus status,
        Instant occurredAt,
        JsonNode data
) {
}
