package com.ssafy.backend.pet.application;

import java.time.Instant;

public record PetCreatedResult(
        Long petId,
        String name,
        PetAffinityResult affinity,
        Instant createdAt
) {
}
