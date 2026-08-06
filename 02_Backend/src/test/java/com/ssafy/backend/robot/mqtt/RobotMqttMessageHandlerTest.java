package com.ssafy.backend.robot.mqtt;

import org.junit.jupiter.api.Test;
import org.springframework.integration.mqtt.support.MqttHeaders;
import org.springframework.messaging.Message;
import org.springframework.messaging.support.MessageBuilder;
import tools.jackson.databind.ObjectMapper;

import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class RobotMqttMessageHandlerTest {

    private final ObjectMapper objectMapper = mock(ObjectMapper.class);
    private final RobotMqttApplicationService mqttService =
            mock(RobotMqttApplicationService.class);
    private final RobotMqttMessageHandler handler =
            new RobotMqttMessageHandler(objectMapper, mqttService);

    @Test
    void acceptsEventWhenTopicAndPayloadDeviceIdsMatch() throws Exception {
        String payload = "{\"deviceId\":\"device-001\"}";
        RobotEventMessage event = event("device-001");
        when(objectMapper.readValue(payload, RobotEventMessage.class))
                .thenReturn(event);

        Message<String> message = message(
                "robot-pet/v1/devices/device-001/events",
                payload
        );

        assertDoesNotThrow(() -> handler.handle(message));
        verify(objectMapper).readValue(payload, RobotEventMessage.class);
        verify(mqttService).processEvent(event);
    }

    @Test
    void rejectsEventWhenTopicAndPayloadDeviceIdsDiffer() throws Exception {
        String payload = "{\"deviceId\":\"device-002\"}";
        when(objectMapper.readValue(payload, RobotEventMessage.class))
                .thenReturn(event("device-002"));

        Message<String> message = message(
                "robot-pet/v1/devices/device-001/events",
                payload
        );

        assertThrows(
                IllegalArgumentException.class,
                () -> handler.handle(message)
        );
    }

    @Test
    void rejectsMessageWithoutReceivedTopic() {
        Message<String> message = MessageBuilder.withPayload("{}").build();

        assertThrows(
                IllegalArgumentException.class,
                () -> handler.handle(message)
        );
    }

    @Test
    void routesHeartbeatToApplicationService() throws Exception {
        String payload = "{\"deviceId\":\"device-001\"}";
        RobotHeartbeatMessage heartbeat = new RobotHeartbeatMessage(
                UUID.randomUUID(),
                "1.0",
                "device-001",
                Instant.parse("2026-07-30T00:00:00Z"),
                75,
                false,
                "IDLE"
        );
        when(objectMapper.readValue(payload, RobotHeartbeatMessage.class))
                .thenReturn(heartbeat);

        handler.handle(message(
                "robot-pet/v1/devices/device-001/heartbeat",
                payload
        ));

        verify(mqttService).processHeartbeat(heartbeat);
    }

    @Test
    void routesRequestResultToApplicationService() throws Exception {
        String payload = "{\"deviceId\":\"device-001\"}";
        RobotRequestResultMessage result = new RobotRequestResultMessage(
                UUID.randomUUID(),
                "1.0",
                "device-001",
                UUID.randomUUID(),
                BehaviorRequestStatus.COMPLETED,
                Instant.parse("2026-07-30T00:00:00Z"),
                null
        );
        when(objectMapper.readValue(
                payload,
                RobotRequestResultMessage.class
        )).thenReturn(result);

        handler.handle(message(
                "robot-pet/v1/devices/device-001/request-results",
                payload
        ));

        verify(mqttService).processRequestResult(result);
    }

    private Message<String> message(String topic, String payload) {
        return MessageBuilder.withPayload(payload)
                .setHeader(MqttHeaders.RECEIVED_TOPIC, topic)
                .build();
    }

    private RobotEventMessage event(String deviceId) {
        return new RobotEventMessage(
                UUID.randomUUID(),
                "1.0",
                deviceId,
                Instant.parse("2026-07-30T00:00:00Z"),
                RobotEventType.WALK_COMPLETED,
                null
        );
    }
}
