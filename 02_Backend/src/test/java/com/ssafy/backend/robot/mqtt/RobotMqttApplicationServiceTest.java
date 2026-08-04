package com.ssafy.backend.robot.mqtt;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.context.ApplicationEventPublisher;
import tools.jackson.databind.ObjectMapper;

import java.time.Instant;
import java.time.LocalDate;
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
    void storesEventUpdatesAffinityAndPublishesChangedScore()
            throws Exception {
        UUID messageId = UUID.randomUUID();
        RobotEventMessage event = new RobotEventMessage(
                messageId,
                "1.0",
                "device-001",
                Instant.parse("2026-08-03T05:00:00Z"),
                RobotEventType.WALK_COMPLETED,
                new ObjectMapper().readTree("""
                        {
                          "startedAt": "2026-08-03T04:30:00Z",
                          "walkDate": "2026-08-03",
                          "session": 1
                        }
                        """)
        );
        when(store.findEventResult(messageId)).thenReturn(Optional.empty());
        when(store.lockAffinity("device-001")).thenReturn(
                new RobotMqttStore.AffinityContext(1L, 10L, 2L, 95)
        );
        AffectionChangedMessage response = service.processEvent(event);

        assertEquals(95, response.previousScore());
        assertEquals(5, response.scoreChange());
        assertEquals(100, response.currentScore());
        assertEquals(5, response.affinityLevel());
        assertEquals("HAPPY", response.mood());
        verify(store).updateAffinity(
                2L,
                100,
                5,
                "HAPPY",
                event.occurredAt()
        );
        verify(store).insertEvent(
                event,
                1L,
                "{\"startedAt\":\"2026-08-03T04:30:00Z\","
                        + "\"walkDate\":\"2026-08-03\",\"session\":1}",
                95,
                5,
                100
        );
        verify(store).insertCompletedWalk(
                10L,
                Instant.parse("2026-08-03T04:30:00Z"),
                Instant.parse("2026-08-03T05:00:00Z"),
                LocalDate.parse("2026-08-03"),
                1,
                "robot-images/device-001/2026-08-03/session1/"
        );
        verify(eventPublisher).publishEvent(
                new AffectionPublishEvent(response)
        );
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
    void rejectsWalkCompletedWithoutDiaryLocationData() {
        RobotEventMessage event = new RobotEventMessage(
                UUID.randomUUID(),
                "1.0",
                "device-001",
                Instant.parse("2026-08-03T05:00:00Z"),
                RobotEventType.WALK_COMPLETED,
                null
        );
        when(store.findEventResult(event.messageId()))
                .thenReturn(Optional.empty());
        when(store.lockAffinity("device-001")).thenReturn(
                new RobotMqttStore.AffinityContext(1L, 10L, 2L, 50)
        );

        assertThrows(
                IllegalArgumentException.class,
                () -> service.processEvent(event)
        );
    }

    @Test
    void rejectsWalkCompletedWithStringSession() throws Exception {
        RobotEventMessage event = new RobotEventMessage(
                UUID.randomUUID(),
                "1.0",
                "device-001",
                Instant.parse("2026-08-03T05:00:00Z"),
                RobotEventType.WALK_COMPLETED,
                new ObjectMapper().readTree("""
                        {
                          "startedAt": "2026-08-03T04:30:00Z",
                          "walkDate": "2026-08-03",
                          "session": "1"
                        }
                        """)
        );
        when(store.findEventResult(event.messageId()))
                .thenReturn(Optional.empty());
        when(store.lockAffinity("device-001")).thenReturn(
                new RobotMqttStore.AffinityContext(1L, 10L, 2L, 50)
        );

        assertThrows(
                IllegalArgumentException.class,
                () -> service.processEvent(event)
        );
    }
}
