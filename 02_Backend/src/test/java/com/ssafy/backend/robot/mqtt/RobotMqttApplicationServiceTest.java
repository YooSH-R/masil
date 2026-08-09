package com.ssafy.backend.robot.mqtt;

import com.ssafy.backend.pet.application.PetAffinityChangedEvent;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.context.ApplicationEventPublisher;
import tools.jackson.databind.ObjectMapper;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class RobotMqttApplicationServiceTest {

    private RobotMqttStore store;
    private ApplicationEventPublisher eventPublisher;
    private RobotMqttApplicationService service;

    @BeforeEach
    void setUp() {
        store = mock(RobotMqttStore.class);
        eventPublisher = mock(ApplicationEventPublisher.class);
        service = new RobotMqttApplicationService(
                store,
                eventPublisher
        );
    }

    @Test
    void storesEventUpdatesAffinityAndPublishesChangedScore() {
        UUID messageId = UUID.randomUUID();
        RobotEventMessage event = new RobotEventMessage(
                messageId,
                "1.0",
                "device-001",
                Instant.parse("2026-08-03T05:00:00Z"),
                RobotEventType.CARE_ACTION,
                null
        );
        when(store.findEventResult(messageId)).thenReturn(Optional.empty());
        when(store.lockAffinity("device-001")).thenReturn(
                new RobotMqttStore.AffinityContext(1L, 10L, 2L, 95)
        );
        AffectionChangedMessage response = service.processEvent(event);

        assertEquals(95, response.previousScore());
        assertEquals(3, response.scoreChange());
        assertEquals(98, response.currentScore());
        assertEquals(5, response.affinityLevel());
        assertEquals("HAPPY", response.mood());
        verify(store).updateAffinity(
                2L,
                98,
                5,
                "HAPPY",
                event.occurredAt()
        );
        verify(store).insertEvent(
                event,
                1L,
                "{}",
                95,
                3,
                98
        );
        verify(eventPublisher).publishEvent(
                new AffectionPublishEvent(response)
        );
        verify(eventPublisher).publishEvent(new PetAffinityChangedEvent(
                2L,
                messageId,
                95,
                3,
                98,
                5,
                "HAPPY",
                response.occurredAt()
        ));
    }

    @Test
    void callAndResponsePublishesAffinityChangeForApp() {
        UUID messageId = UUID.randomUUID();
        RobotEventMessage event = new RobotEventMessage(
                messageId,
                "1.0",
                "device-001",
                Instant.parse("2026-08-07T01:00:00Z"),
                RobotEventType.CALL_AND_RESPONSE,
                null
        );
        when(store.findEventResult(messageId)).thenReturn(Optional.empty());
        when(store.lockAffinity("device-001")).thenReturn(
                new RobotMqttStore.AffinityContext(1L, 10L, 2L, 6)
        );

        AffectionChangedMessage response = service.processEvent(event);

        assertEquals(8, response.currentScore());
        assertEquals(2, response.scoreChange());
        verify(eventPublisher).publishEvent(new PetAffinityChangedEvent(
                2L,
                messageId,
                6,
                2,
                8,
                1,
                "WARY",
                response.occurredAt()
        ));
    }

    @Test
    void doesNotUpdateLastInteractionForLongInactivity()
            throws Exception {
        UUID messageId = UUID.randomUUID();
        RobotEventMessage event = new RobotEventMessage(
                messageId,
                "1.0",
                "device-001",
                Instant.parse("2026-07-30T00:00:00Z"),
                RobotEventType.LONG_INACTIVITY,
                null
        );
        when(store.findEventResult(messageId)).thenReturn(Optional.empty());
        when(store.lockAffinity("device-001")).thenReturn(
                new RobotMqttStore.AffinityContext(1L, 10L, 2L, 10)
        );
        service.processEvent(event);

        verify(store).updateAffinity(2L, 9, 1, "WARY", null);
    }

    @Test
    void appliesWalkCompletedEventToWalkPairingPet() throws Exception {
        UUID messageId = UUID.randomUUID();
        RobotEventMessage event = new RobotEventMessage(
                messageId,
                "1.0",
                "device-001",
                Instant.parse("2026-08-03T03:00:00Z"),
                RobotEventType.WALK_COMPLETED,
                new ObjectMapper().readTree("{\"walkId\":101}")
        );
        when(store.findEventResult(messageId, 2L))
                .thenReturn(Optional.empty());
        when(store.lockAffinity(1L, 2L, "device-001")).thenReturn(
                new RobotMqttStore.AffinityContext(1L, 2L, 50)
        );

        AffectionChangedMessage response = service.processWalkCompletedEvent(
                event,
                1L,
                2L
        );

        assertEquals(50, response.previousScore());
        assertEquals(10, response.scoreChange());
        assertEquals(60, response.currentScore());
        verify(store).updateAffinity(
                2L,
                60,
                4,
                "FRIENDLY",
                event.occurredAt()
        );
        verify(store).insertEvent(
                event,
                1L,
                "{\"walkId\":101}",
                50,
                10,
                60
        );
    }

    @Test
    void rejectsInvalidHeartbeatBatteryLevel() {
        RobotHeartbeatMessage heartbeat = new RobotHeartbeatMessage(
                UUID.randomUUID(),
                "1.0",
                "device-001",
                Instant.parse("2026-07-30T00:00:00Z"),
                101,
                false,
                "IDLE"
        );

        assertThrows(
                IllegalArgumentException.class,
                () -> service.processHeartbeat(heartbeat)
        );
    }

    @Test
    void rejectsWalkCompletedFromInboundDeviceChannel() throws Exception {
        RobotEventMessage event = new RobotEventMessage(
                UUID.randomUUID(),
                "1.0",
                "device-001",
                Instant.parse("2026-08-03T05:00:00Z"),
                RobotEventType.WALK_COMPLETED,
                new ObjectMapper().readTree("{\"walkId\":101}")
        );

        assertThrows(
                IllegalArgumentException.class,
                () -> service.processEvent(event)
        );
    }

    @Test
    void acceptsInternalWalkCompletedWithoutDiaryMetadata() {
        RobotEventMessage event = new RobotEventMessage(
                UUID.randomUUID(),
                "1.0",
                "device-001",
                Instant.parse("2026-08-03T05:00:00Z"),
                RobotEventType.WALK_COMPLETED,
                null
        );
        when(store.findEventResult(event.messageId(), 2L))
                .thenReturn(Optional.empty());
        when(store.lockAffinity(1L, 2L, "device-001")).thenReturn(
                new RobotMqttStore.AffinityContext(1L, 2L, 50)
        );

        AffectionChangedMessage response = service.processWalkCompletedEvent(
                event,
                1L,
                2L
        );

        assertEquals(60, response.currentScore());
        verify(store).insertEvent(event, 1L, "{}", 50, 10, 60);
    }
}
