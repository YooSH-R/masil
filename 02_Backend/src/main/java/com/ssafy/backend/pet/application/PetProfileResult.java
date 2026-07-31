package com.ssafy.backend.pet.application;

public record PetProfileResult(
        Long petId,
        String name,
        String profileImageUrl,
        PetAffinityResult affinity,
        PetRobotResult robot
) {
}
