package com.ssafy.backend.robot.mqtt;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;
import tools.jackson.databind.ObjectMapper;

@Component
@ConditionalOnProperty(name = "mqtt.enabled", havingValue = "true")
class AffectionPublishListener {

    private static final Logger log = LoggerFactory.getLogger(
            AffectionPublishListener.class
    );

    private final RobotMqttPublisher publisher;
    private final ObjectMapper objectMapper;

    AffectionPublishListener(
            RobotMqttPublisher publisher,
            ObjectMapper objectMapper
    ) {
        this.publisher = publisher;
        this.objectMapper = objectMapper;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void publish(AffectionPublishEvent event) {
        AffectionChangedMessage message = event.message();
        try {
            publisher.publish(
                    RobotMqttTopics.affection(message.deviceId()),
                    1,
                    objectMapper.writeValueAsString(message)
            );
        } catch (Exception exception) {
            log.error(
                    "호감도 변경 MQTT 발행에 실패했습니다. eventMessageId={}",
                    message.eventMessageId(),
                    exception
            );
        }
    }
}
