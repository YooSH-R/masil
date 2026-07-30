package com.ssafy.backend.robot.mqtt;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.integration.annotation.ServiceActivator;
import org.springframework.integration.mqtt.support.MqttHeaders;
import org.springframework.messaging.Message;
import org.springframework.stereotype.Component;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;

@Component
@ConditionalOnProperty(name = "mqtt.enabled", havingValue = "true")
public class RobotMqttMessageHandler {

    private final ObjectMapper objectMapper;
    private final RobotMqttApplicationService mqttService;

    public RobotMqttMessageHandler(
            ObjectMapper objectMapper,
            RobotMqttApplicationService mqttService
    ) {
        this.objectMapper = objectMapper;
        this.mqttService = mqttService;
    }

    @ServiceActivator(inputChannel = "mqttInboundChannel")
    public void handle(Message<String> message) throws JacksonException {
        String topic = message.getHeaders().get(
                MqttHeaders.RECEIVED_TOPIC,
                String.class
        );
        if (topic == null) {
            throw new IllegalArgumentException("MQTT 수신 토픽이 없습니다.");
        }

        String topicDeviceId = RobotMqttTopics.deviceIdFrom(topic);
        if (topic.endsWith("/events")) {
            RobotEventMessage event = objectMapper.readValue(
                    message.getPayload(),
                    RobotEventMessage.class
            );
            requireMatchingDeviceId(topicDeviceId, event.deviceId());
            mqttService.processEvent(event);
            return;
        }
        if (topic.endsWith("/heartbeat")) {
            RobotHeartbeatMessage heartbeat = objectMapper.readValue(
                    message.getPayload(),
                    RobotHeartbeatMessage.class
            );
            requireMatchingDeviceId(topicDeviceId, heartbeat.deviceId());
            mqttService.processHeartbeat(heartbeat);
            return;
        }
        if (topic.endsWith("/request-results")) {
            RobotRequestResultMessage result = objectMapper.readValue(
                    message.getPayload(),
                    RobotRequestResultMessage.class
            );
            requireMatchingDeviceId(topicDeviceId, result.deviceId());
            mqttService.processRequestResult(result);
            return;
        }
        throw new IllegalArgumentException("지원하지 않는 MQTT 토픽입니다.");
    }

    private void requireMatchingDeviceId(
            String topicDeviceId,
            String messageDeviceId
    ) {
        if (!topicDeviceId.equals(messageDeviceId)) {
            throw new IllegalArgumentException(
                    "토픽과 메시지의 deviceId가 다릅니다."
            );
        }
    }
}
