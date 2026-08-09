package com.ssafy.backend.robot.mqtt;

import java.time.Instant;
import java.util.UUID;

public record RobotHeartbeatMessage(
        UUID messageId,
        String messageVersion,
        String deviceId,
        Instant occurredAt,
        int batteryLevel,
        boolean docked,
        String mode
) {
}
