package com.ssafy.backend.robot.mqtt;

import org.springframework.integration.annotation.MessagingGateway;
import org.springframework.integration.mqtt.support.MqttHeaders;
import org.springframework.messaging.handler.annotation.Header;

@MessagingGateway(defaultRequestChannel = "mqttOutboundChannel")
public interface RobotMqttPublisher {

    void publish(
            @Header(MqttHeaders.TOPIC) String topic,
            @Header(MqttHeaders.QOS) int qos,
            String payload
    );
}
