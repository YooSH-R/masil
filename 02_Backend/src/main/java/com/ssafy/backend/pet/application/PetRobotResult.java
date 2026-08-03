package com.ssafy.backend.pet.application;

public record PetRobotResult(
        Long robotId,
        boolean online,
        int batteryLevel
) {
}
