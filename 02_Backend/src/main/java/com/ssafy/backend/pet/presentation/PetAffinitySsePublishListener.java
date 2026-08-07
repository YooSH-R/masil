package com.ssafy.backend.pet.presentation;

import com.ssafy.backend.pet.application.PetAffinityChangedEvent;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

@Component
class PetAffinitySsePublishListener {

    private final PetAffinitySseRegistry sseRegistry;

    PetAffinitySsePublishListener(PetAffinitySseRegistry sseRegistry) {
        this.sseRegistry = sseRegistry;
    }

    @Async("petAffinitySseExecutor")
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void publish(PetAffinityChangedEvent event) {
        sseRegistry.broadcast(event);
    }
}
