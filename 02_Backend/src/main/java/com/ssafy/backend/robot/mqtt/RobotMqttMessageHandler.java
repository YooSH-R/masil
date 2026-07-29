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

    public RobotMqttMessageHandler(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    @ServiceActivator(inputChannel = "mqttInboundChannel")
    public void handle(Message<String> message) throws JacksonException {
        String topic = message.getHeaders().get(MqttHeaders.RECEIVED_TOPIC, String.class);
        if (topic == null) {
            throw new IllegalArgumentException("MQTT 수신 토픽이 없습니다.");
        }

        String topicDeviceId = RobotMqttTopics.deviceIdFrom(topic);
        if (topic.endsWith("/events")) {
            RobotEventMessage event = objectMapper.readValue(
                    message.getPayload(),
                    RobotEventMessage.class
            );
            if (!topicDeviceId.equals(event.deviceId())) {
                throw new IllegalArgumentException("토픽과 메시지의 deviceId가 다릅니다.");
            }
        }
        // heartbeat와 request-results 처리는 후속 애플리케이션 서비스에서 연결한다.
    }
}
