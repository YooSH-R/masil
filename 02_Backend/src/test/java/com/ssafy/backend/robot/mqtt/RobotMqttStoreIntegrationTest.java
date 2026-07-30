package com.ssafy.backend.robot.mqtt;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

@SpringBootTest(properties = {
        "solapi.api-key=test",
        "solapi.secret-key=test",
        "solapi.sender=01000000000"
})
@ActiveProfiles("s3local")
@Transactional
class RobotMqttStoreIntegrationTest {

    @Autowired
    private RobotMqttStore store;

    @Test
    void storesAffinityEventAndReadsIdempotentResult() {
        RobotMqttStore.AffinityContext context =
                store.lockAffinity("device-001");
        UUID messageId = UUID.randomUUID();
        RobotEventMessage event = new RobotEventMessage(
                messageId,
                "1.0",
                "device-001",
                Instant.parse("2026-07-30T00:00:00Z"),
                RobotEventType.CARE_ACTION,
                null
        );

        store.updateAffinity(
                context.petId(),
                53,
                3,
                "FRIENDLY",
                event.occurredAt()
        );
        store.insertEvent(
                event,
                context.robotId(),
                "{}",
                50,
                3,
                53
        );

        RobotMqttStore.AffectionResult result =
                store.findEventResult(messageId).orElseThrow();
        assertEquals(50, result.previousScore());
        assertEquals(53, result.currentScore());
    }

    @Test
    void upsertsHeartbeatAndKeepsMessageIdIdempotent() {
        RobotHeartbeatMessage heartbeat = new RobotHeartbeatMessage(
                UUID.randomUUID(),
                "1.0",
                "device-001",
                Instant.parse("2026-07-30T00:00:00Z"),
                65,
                false,
                "IDLE"
        );

        store.upsertHeartbeat(heartbeat);
        store.upsertHeartbeat(heartbeat);

        RobotMqttStore.RequestCandidate candidate =
                store.findRequestCandidates().get(0);
        assertEquals(65, candidate.batteryLevel());
    }

    @Test
    void createsAndCompletesBehaviorRequest() {
        RobotMqttStore.RequestCandidate candidate =
                store.findRequestCandidates().get(0);
        Instant now = Instant.parse("2026-07-30T00:00:00Z");
        BehaviorRequestMessage request = store.createRequest(
                candidate,
                BehaviorRequestType.WALK_REQUEST,
                "산책해요.",
                now,
                now.plusSeconds(1800)
        );
        store.markRequestPublished(request.requestId(), now);

        assertTrue(store.hasOpenRequest(
                candidate.robotId(),
                BehaviorRequestType.WALK_REQUEST
        ));

        store.updateRequestResult(new RobotRequestResultMessage(
                UUID.randomUUID(),
                "1.0",
                candidate.deviceId(),
                request.requestId(),
                BehaviorRequestStatus.COMPLETED,
                now.plusSeconds(60),
                null
        ));

        assertFalse(store.hasOpenRequest(
                candidate.robotId(),
                BehaviorRequestType.WALK_REQUEST
        ));
    }
}
