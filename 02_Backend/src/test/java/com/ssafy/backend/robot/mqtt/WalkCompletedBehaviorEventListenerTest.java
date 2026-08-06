package com.ssafy.backend.robot.mqtt;

import com.ssafy.backend.walk.application.WalkCompletedDomainEvent;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import tools.jackson.databind.ObjectMapper;

import java.time.Instant;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

class WalkCompletedBehaviorEventListenerTest {

    @Test
    void mapsWalkCompletionToStableBehaviorEvent() {
        RobotMqttApplicationService mqttService = mock(
                RobotMqttApplicationService.class
        );
        WalkCompletedBehaviorEventListener listener =
                new WalkCompletedBehaviorEventListener(
                        mqttService,
                        new ObjectMapper()
                );
        Instant occurredAt = Instant.parse("2026-08-03T03:00:00Z");

        listener.handle(new WalkCompletedDomainEvent(
                501L,
                11L,
                21L,
                "device-001",
                occurredAt,
                1200,
                850
        ));

        ArgumentCaptor<RobotEventMessage> eventCaptor =
                ArgumentCaptor.forClass(RobotEventMessage.class);
        verify(mqttService).processWalkCompletedEvent(
                eventCaptor.capture(),
                org.mockito.ArgumentMatchers.eq(11L),
                org.mockito.ArgumentMatchers.eq(21L)
        );
        RobotEventMessage event = eventCaptor.getValue();
        assertEquals(
                WalkCompletedBehaviorEventListener.messageIdFor(501L),
                event.messageId()
        );
        assertEquals("device-001", event.deviceId());
        assertEquals(occurredAt, event.occurredAt());
        assertEquals(RobotEventType.WALK_COMPLETED, event.eventType());
        assertEquals(501L, event.data().get("walkId").asLong());
        assertEquals(1200, event.data().get("durationSeconds").asInt());
        assertEquals(850, event.data().get("distanceMeters").asInt());
    }
}
