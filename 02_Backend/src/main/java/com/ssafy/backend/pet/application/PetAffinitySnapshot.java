package com.ssafy.backend.pet.application;

import java.time.Instant;

public record PetAffinitySnapshot(
        long petId,
        int score,
        int level,
        String mood,
        Instant updatedAt
) {
}
