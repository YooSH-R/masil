package com.ssafy.backend.robot.mqtt;

import org.junit.jupiter.api.Test;
import tools.jackson.databind.ObjectMapper;

import java.time.Instant;
import java.util.UUID;

import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class BehaviorRequestPublishListenerTest {

    @Test
    void marksRequestPublishedAfterMqttAcceptsMessage() throws Exception {
        RobotMqttPublisher publisher = mock(RobotMqttPublisher.class);
        BehaviorRequestPublicationService publicationService =
                mock(BehaviorRequestPublicationService.class);
        ObjectMapper objectMapper = mock(ObjectMapper.class);
        BehaviorRequestPublishListener listener =
                new BehaviorRequestPublishListener(
                        publisher,
                        publicationService,
                        objectMapper
                );
        BehaviorRequestMessage request = request();
        Instant publishedAt = Instant.parse("2026-07-31T00:01:00Z");
        when(objectMapper.writeValueAsString(request)).thenReturn("{}");

        listener.publish(
                new BehaviorRequestPublishEvent(request, publishedAt)
        );

        verify(publisher).publish(
                RobotMqttTopics.requests("device-001"),
                1,
                "{}"
        );
        verify(publicationService).markPublished(
                request.requestId(),
                publishedAt
        );
    }

    @Test
    void leavesRequestPendingWhenMqttPublishFails() throws Exception {
        RobotMqttPublisher publisher = mock(RobotMqttPublisher.class);
        BehaviorRequestPublicationService publicationService =
                mock(BehaviorRequestPublicationService.class);
        ObjectMapper objectMapper = mock(ObjectMapper.class);
        BehaviorRequestPublishListener listener =
                new BehaviorRequestPublishListener(
                        publisher,
                        publicationService,
                        objectMapper
                );
        BehaviorRequestMessage request = request();
        when(objectMapper.writeValueAsString(request)).thenReturn("{}");
        doThrow(new IllegalStateException("broker unavailable"))
                .when(publisher)
                .publish(
                        RobotMqttTopics.requests("device-001"),
                        1,
                        "{}"
                );

        listener.publish(
                new BehaviorRequestPublishEvent(
                        request,
                        Instant.parse("2026-07-31T00:01:00Z")
                )
        );

        verify(publicationService, never()).markPublished(
                org.mockito.ArgumentMatchers.any(UUID.class),
                org.mockito.ArgumentMatchers.any(Instant.class)
        );
    }

    private BehaviorRequestMessage request() {
        return new BehaviorRequestMessage(
                UUID.randomUUID(),
                "1.0",
                "device-001",
                BehaviorRequestType.WALK_REQUEST,
                "함께 산책해요.",
                Instant.parse("2026-07-31T00:00:00Z"),
                Instant.parse("2026-07-31T00:30:00Z")
        );
    }
}
