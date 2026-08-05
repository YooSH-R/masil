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
class BehaviorRequestPublishListener {

    private static final Logger log = LoggerFactory.getLogger(
            BehaviorRequestPublishListener.class
    );

    private final RobotMqttPublisher publisher;
    private final BehaviorRequestPublicationService publicationService;
    private final ObjectMapper objectMapper;

    BehaviorRequestPublishListener(
            RobotMqttPublisher publisher,
            BehaviorRequestPublicationService publicationService,
            ObjectMapper objectMapper
    ) {
        this.publisher = publisher;
        this.publicationService = publicationService;
        this.objectMapper = objectMapper;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void publish(BehaviorRequestPublishEvent event) {
        BehaviorRequestMessage request = event.request();
        try {
            publisher.publish(
                    RobotMqttTopics.requests(request.deviceId()),
                    1,
                    objectMapper.writeValueAsString(request)
            );
            publicationService.markPublished(
                    request.requestId(),
                    event.publishedAt()
            );
        } catch (Exception exception) {
            log.error(
                    "행동 요청 MQTT 발행에 실패했습니다. 다음 스케줄에서 재시도합니다. requestId={}",
                    request.requestId(),
                    exception
            );
        }
    }
}
