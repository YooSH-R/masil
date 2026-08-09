package com.ssafy.backend.robot.application;

public record RobotRegistrationPreview(
        String serialNumber,
        String modelName,
        String firmwareVersion
) {
}
