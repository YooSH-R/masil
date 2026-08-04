package com.ssafy.backend.robot.mqtt;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
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

    @Autowired
    private JdbcTemplate jdbcTemplate;

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

    @ParameterizedTest
    @ValueSource(strings = {"REJECTED", "EXPIRED"})
    void recentWalkRequestCooldownIncludesTerminalStatuses(String status) {
        RobotMqttStore.RequestCandidate candidate =
                store.findRequestCandidates().get(0);
        Instant now = Instant.parse("2026-07-30T00:00:00Z");
        BehaviorRequestMessage request = store.createRequest(
                candidate,
                BehaviorRequestType.WALK_REQUEST,
                "walk",
                now,
                now.plusSeconds(1800)
        );
        jdbcTemplate.update(
                "UPDATE behavior_requests SET status = ? WHERE request_id = ?",
                status,
                request.requestId()
        );

        assertTrue(store.hasRecentRequest(
                candidate.robotId(),
                BehaviorRequestType.WALK_REQUEST,
                now.minusSeconds(10_800)
        ));
        assertFalse(store.hasRecentRequest(
                candidate.robotId(),
                BehaviorRequestType.WALK_REQUEST,
                now
        ));
    }

    @Test
    void createsDiaryForExistingCompletedWalkIdempotently() {
        RobotMqttStore.AffinityContext context =
                store.lockAffinity("device-001");
        jdbcTemplate.update("""
                INSERT INTO walks (
                    robot_pairing_id, status, started_at, ended_at,
                    distance_meters, duration_seconds, created_at, updated_at
                ) VALUES (?, 'COMPLETED', ?, ?, 1200.00, 1800,
                          CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """,
                context.pairingId(),
                java.sql.Timestamp.from(Instant.parse(
                        "2026-08-03T04:30:00Z"
                )),
                java.sql.Timestamp.from(Instant.parse(
                        "2026-08-03T05:00:00Z"
                ))
        );
        Long walkId = jdbcTemplate.queryForObject("""
                SELECT MAX(id) FROM walks WHERE robot_pairing_id = ?
                """,
                Long.class,
                context.pairingId()
        );

        store.createWalkDiary(walkId, "device-001");
        store.createWalkDiary(walkId, "device-001");

        assertEquals(
                1,
                jdbcTemplate.queryForObject(
                        "SELECT COUNT(*) FROM walk_diaries WHERE walk_id = ?",
                        Integer.class,
                        walkId
                )
        );
    }
}
