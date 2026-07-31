package com.ssafy.backend.pet.application;

public record PetAffinityResult(
        int score,
        int level,
        String mood
) {
}
