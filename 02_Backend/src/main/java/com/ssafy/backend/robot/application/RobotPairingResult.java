package com.ssafy.backend.robot.application;

import java.time.Instant;

public record RobotPairingResult(
        Long pairingId,
        Long robotId,
        Long petId,
        String serialNumber,
        String modelName,
        String firmwareVersion,
        Instant pairedAt
) {
}
