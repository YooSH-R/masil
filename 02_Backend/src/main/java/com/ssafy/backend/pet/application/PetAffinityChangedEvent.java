package com.ssafy.backend.pet.application;

import java.time.Instant;
import java.util.UUID;

public record PetAffinityChangedEvent(
        long petId,
        UUID eventMessageId,
        int previousScore,
        int scoreChange,
        int currentScore,
        int affinityLevel,
        String mood,
        Instant occurredAt
) {
}
