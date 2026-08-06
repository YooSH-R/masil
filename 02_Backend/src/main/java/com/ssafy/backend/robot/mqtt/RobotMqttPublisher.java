package com.ssafy.backend.robot.mqtt;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.integration.mqtt.support.MqttHeaders;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.support.MessageBuilder;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(name = "mqtt.enabled", havingValue = "true")
public class RobotMqttPublisher {

    private final MessageChannel outboundChannel;

    public RobotMqttPublisher(
            @Qualifier("mqttOutboundChannel")
            MessageChannel outboundChannel
    ) {
        this.outboundChannel = outboundChannel;
    }

    public void publish(String topic, int qos, String payload) {
        boolean accepted = outboundChannel.send(
                MessageBuilder.withPayload(payload)
                        .setHeader(MqttHeaders.TOPIC, topic)
                        .setHeader(MqttHeaders.QOS, qos)
                        .build()
        );
        if (!accepted) {
            throw new IllegalStateException(
                    "MQTT 발행 채널이 메시지를 수락하지 않았습니다."
            );
        }
    }
}
