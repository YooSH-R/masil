package com.ssafy.backend.pet.presentation;

import com.ssafy.backend.pet.application.PetAffinityChangedEvent;
import org.junit.jupiter.api.Test;
import org.springframework.scheduling.annotation.Async;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

import java.lang.reflect.Method;
import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
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
    void publishesOnlyAfterCommitOnDedicatedExecutor() throws Exception {
        Method method = PetAffinitySsePublishListener.class.getDeclaredMethod(
                "publish",
                PetAffinityChangedEvent.class
        );
        TransactionalEventListener listener = method.getAnnotation(
                TransactionalEventListener.class
        );
        Async async = method.getAnnotation(Async.class);

        assertNotNull(listener);
        assertNotNull(async);
        assertEquals(TransactionPhase.AFTER_COMMIT, listener.phase());
        assertEquals("petAffinitySseExecutor", async.value());
    }
}
