package com.ssafy.backend.pet.application;

public record PetProfileResult(
        Long petId,
        String name,
        String profileImageUrl,
        int dailyWalkCount,
        PetAffinityResult affinity,
        PetRobotResult robot
) {
}
