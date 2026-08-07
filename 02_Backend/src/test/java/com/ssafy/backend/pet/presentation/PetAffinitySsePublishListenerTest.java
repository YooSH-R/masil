package com.ssafy.backend.pet.presentation;

import com.ssafy.backend.pet.application.PetAffinityChangedEvent;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

import java.lang.reflect.Method;
import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

class PetAffinitySsePublishListenerTest {

    @Test
    void broadcastsCommittedAffinityChange() {
        PetAffinitySseRegistry registry = mock(PetAffinitySseRegistry.class);
        PetAffinitySsePublishListener listener =
                new PetAffinitySsePublishListener(registry);
        PetAffinityChangedEvent event = new PetAffinityChangedEvent(
                5L,
                UUID.randomUUID(),
                6,
                2,
                8,
                1,
                "WARY",
                Instant.parse("2026-08-07T01:00:00Z")
        );

        listener.publish(event);

        verify(registry).broadcast(event);
    }

    @Test
    void publishesOnlyAfterCommitWithoutAsyncTransactionThreadFallback()
            throws Exception {
        Method method = PetAffinitySsePublishListener.class.getDeclaredMethod(
                "publish",
                PetAffinityChangedEvent.class
        );
        TransactionalEventListener listener = method.getAnnotation(
                TransactionalEventListener.class
        );

        assertNotNull(listener);
        assertEquals(TransactionPhase.AFTER_COMMIT, listener.phase());
        assertNull(method.getAnnotation(
                org.springframework.scheduling.annotation.Async.class
        ));
    }
}
