package com.ssafy.backend.robot.mqtt;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.UUID;

@Service
@ConditionalOnProperty(name = "mqtt.enabled", havingValue = "true")
class BehaviorRequestPublicationService {

    private final RobotMqttStore store;

    BehaviorRequestPublicationService(RobotMqttStore store) {
        this.store = store;
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    void markPublished(UUID requestId, Instant publishedAt) {
        store.markRequestPublished(requestId, publishedAt);
    }
}
