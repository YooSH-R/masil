package com.ssafy.backend.pet.presentation;

import com.ssafy.backend.pet.application.PetAffinityChangedEvent;
import com.ssafy.backend.pet.application.PetAffinitySnapshot;

import java.time.Instant;
import java.util.UUID;

public record PetAffinitySsePayload(
        long petId,
        int score,
        Integer change,
        Integer previousScore,
        int level,
        String mood,
        UUID eventMessageId,
        Instant updatedAt
) {

    static PetAffinitySsePayload snapshot(PetAffinitySnapshot snapshot) {
        return new PetAffinitySsePayload(
                snapshot.petId(),
                snapshot.score(),
                null,
                null,
                snapshot.level(),
                snapshot.mood(),
                null,
                snapshot.updatedAt()
        );
    }

    static PetAffinitySsePayload changed(PetAffinityChangedEvent event) {
        return new PetAffinitySsePayload(
                event.petId(),
                event.currentScore(),
                event.scoreChange(),
                event.previousScore(),
                event.affinityLevel(),
                event.mood(),
                event.eventMessageId(),
                event.occurredAt()
        );
    }
}
