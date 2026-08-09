package com.ssafy.backend.robot.mqtt;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public class RobotMqttStore {

    private final JdbcTemplate jdbcTemplate;

    public RobotMqttStore(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    Optional<AffectionResult> findEventResult(UUID messageId) {
        return jdbcTemplate.query("""
                SELECT r.serial_number, e.message_id, e.previous_score,
                       e.score_change, e.current_score, a.affinity_level,
                       a.mood, e.occurred_at
                FROM device_events e
                JOIN robots r ON r.id = e.robot_id
                JOIN robot_pairings rp
                  ON rp.robot_id = r.id AND rp.unpaired_at IS NULL
                JOIN pet_affinity_states a ON a.pet_id = rp.pet_id
                WHERE e.message_id = ?
                """,
                (rs, rowNum) -> new AffectionResult(
                        rs.getString("serial_number"),
                        rs.getObject("message_id", UUID.class),
                        rs.getInt("previous_score"),
                        rs.getInt("score_change"),
                        rs.getInt("current_score"),
                        rs.getInt("affinity_level"),
                        rs.getString("mood"),
                        rs.getTimestamp("occurred_at").toInstant()
                ),
                messageId
        ).stream().findFirst();
    }

    Optional<AffectionResult> findEventResult(UUID messageId, long petId) {
        return jdbcTemplate.query("""
                SELECT r.serial_number, e.message_id, e.previous_score,
                       e.score_change, e.current_score, a.affinity_level,
                       a.mood, e.occurred_at
                FROM device_events e
                JOIN robots r ON r.id = e.robot_id
                JOIN pet_affinity_states a ON a.pet_id = ?
                WHERE e.message_id = ?
                """,
                (rs, rowNum) -> new AffectionResult(
                        rs.getString("serial_number"),
                        rs.getObject("message_id", UUID.class),
                        rs.getInt("previous_score"),
                        rs.getInt("score_change"),
                        rs.getInt("current_score"),
                        rs.getInt("affinity_level"),
                        rs.getString("mood"),
                        rs.getTimestamp("occurred_at").toInstant()
                ),
                petId,
                messageId
        ).stream().findFirst();
    }

    AffinityContext lockAffinity(String deviceId) {
        List<AffinityContext> contexts = jdbcTemplate.query("""
                SELECT r.id AS robot_id, rp.id AS pairing_id,
                       rp.pet_id, a.affinity_score
                FROM robots r
                JOIN robot_pairings rp
                  ON rp.robot_id = r.id AND rp.unpaired_at IS NULL
                JOIN pet_affinity_states a ON a.pet_id = rp.pet_id
                WHERE r.serial_number = ?
                FOR UPDATE OF a
                """,
                (rs, rowNum) -> new AffinityContext(
                        rs.getLong("robot_id"),
                        rs.getLong("pairing_id"),
                        rs.getLong("pet_id"),
                        rs.getInt("affinity_score")
                ),
                deviceId
        );
        if (contexts.size() != 1) {
            throw new IllegalArgumentException(
                    "활성 페어링이 없는 deviceId입니다."
            );
        }
        return contexts.get(0);
    }

    AffinityContext lockAffinity(
            long robotId,
            long petId,
            String deviceId
    ) {
        List<AffinityContext> contexts = jdbcTemplate.query("""
                SELECT r.id AS robot_id, a.pet_id, a.affinity_score
                FROM robots r
                JOIN pet_affinity_states a ON a.pet_id = ?
                WHERE r.id = ?
                  AND r.serial_number = ?
                  AND EXISTS (
                    SELECT 1
                    FROM robot_pairings rp
                    WHERE rp.robot_id = r.id
                      AND rp.pet_id = a.pet_id
                  )
                FOR UPDATE
                """,
                (rs, rowNum) -> new AffinityContext(
                        rs.getLong("robot_id"),
                        rs.getLong("pet_id"),
                        rs.getInt("affinity_score")
                ),
                petId,
                robotId,
                deviceId
        );
        if (contexts.size() != 1) {
            throw new IllegalArgumentException(
                    "산책 페어링과 일치하지 않는 디바이스입니다."
            );
        }
        return contexts.get(0);
    }

    void updateAffinity(
            long petId,
            int score,
            int level,
            String mood,
            Instant interactionAt
    ) {
        jdbcTemplate.update("""
                UPDATE pet_affinity_states
                SET affinity_score = ?,
                    affinity_level = ?,
                    mood = ?,
                    last_interaction_at = COALESCE(?, last_interaction_at),
                    version = version + 1,
                    updated_at = CURRENT_TIMESTAMP
                WHERE pet_id = ?
                """,
                score,
                level,
                mood,
                interactionAt == null ? null : Timestamp.from(interactionAt),
                petId
        );
    }

    void insertEvent(
            RobotEventMessage event,
            long robotId,
            String payload,
            int previousScore,
            int appliedChange,
            int currentScore
    ) {
        jdbcTemplate.update("""
                INSERT INTO device_events (
                    message_id, robot_id, event_type, payload,
                    previous_score, score_change, current_score, occurred_at
                ) VALUES (?, ?, ?, CAST(? AS JSON), ?, ?, ?, ?)
                """,
                event.messageId(),
                robotId,
                event.eventType().name(),
                payload,
                previousScore,
                appliedChange,
                currentScore,
                Timestamp.from(event.occurredAt())
        );
    }

    void upsertHeartbeat(RobotHeartbeatMessage heartbeat) {
        int updated = jdbcTemplate.update("""
                UPDATE robot_current_states s
                SET online = TRUE,
                    mode = ?,
                    battery_level = ?,
                    docked = ?,
                    last_seen_at = ?,
                    last_message_id = ?,
                    updated_at = CURRENT_TIMESTAMP
                FROM robots r
                WHERE s.robot_id = r.id
                  AND r.serial_number = ?
                  AND (s.last_message_id IS NULL OR s.last_message_id <> ?)
                """,
                heartbeat.mode(),
                heartbeat.batteryLevel(),
                heartbeat.docked(),
                Timestamp.from(heartbeat.occurredAt()),
                heartbeat.messageId(),
                heartbeat.deviceId(),
                heartbeat.messageId()
        );
        if (updated == 0) {
            Integer duplicate = jdbcTemplate.queryForObject("""
                    SELECT COUNT(*)
                    FROM robot_current_states s
                    JOIN robots r ON r.id = s.robot_id
                    WHERE r.serial_number = ? AND s.last_message_id = ?
                    """,
                    Integer.class,
                    heartbeat.deviceId(),
                    heartbeat.messageId()
            );
            if (duplicate != null && duplicate == 1) {
                return;
            }
            int inserted = jdbcTemplate.update("""
                    INSERT INTO robot_current_states (
                        robot_id, online, mode, battery_level, docked,
                        last_seen_at, last_message_id
                    )
                    SELECT id, TRUE, ?, ?, ?, ?, ?
                    FROM robots
                    WHERE serial_number = ?
                    ON CONFLICT (robot_id) DO NOTHING
                    """,
                    heartbeat.mode(),
                    heartbeat.batteryLevel(),
                    heartbeat.docked(),
                    Timestamp.from(heartbeat.occurredAt()),
                    heartbeat.messageId(),
                    heartbeat.deviceId()
            );
            if (inserted == 0) {
                throw new IllegalArgumentException(
                        "등록되지 않은 deviceId입니다."
                );
            }
        }
    }

    void updateRequestResult(RobotRequestResultMessage result) {
        String timestampColumn = switch (result.status()) {
            case RECEIVED -> "received_at";
            case COMPLETED -> "completed_at";
            case REJECTED -> "completed_at";
        };
        String allowedCurrentStatuses = switch (result.status()) {
            case RECEIVED -> "'PUBLISHED'";
            case COMPLETED, REJECTED -> "'PUBLISHED', 'RECEIVED'";
        };
        int updated = jdbcTemplate.update("""
                UPDATE behavior_requests b
                SET status = ?,
                    %s = ?,
                    last_result_message_id = ?
                FROM robots r
                WHERE b.robot_id = r.id
                  AND r.serial_number = ?
                  AND b.request_id = ?
                  AND b.status IN (%s)
                  AND (
                    b.last_result_message_id IS NULL
                    OR b.last_result_message_id <> ?
                  )
                """.formatted(timestampColumn, allowedCurrentStatuses),
                result.status().name(),
                Timestamp.from(result.occurredAt()),
                result.messageId(),
                result.deviceId(),
                result.requestId(),
                result.messageId()
        );
        if (updated == 0) {
            Integer duplicate = jdbcTemplate.queryForObject("""
                    SELECT COUNT(*)
                    FROM behavior_requests b
                    JOIN robots r ON r.id = b.robot_id
                    WHERE r.serial_number = ?
                      AND b.request_id = ?
                      AND b.last_result_message_id = ?
                    """,
                    Integer.class,
                    result.deviceId(),
                    result.requestId(),
                    result.messageId()
            );
            if (duplicate == null || duplicate != 1) {
                throw new IllegalArgumentException(
                        "처리할 수 없는 행동 요청 결과입니다."
                );
            }
        }
    }

    List<RequestCandidate> findRequestCandidates() {
        return jdbcTemplate.query("""
                SELECT r.id AS robot_id, r.serial_number,
                       COALESCE(a.affinity_score, 0) AS affinity_score,
                       a.last_interaction_at,
                       s.battery_level,
                       s.mode,
                       (
                         SELECT MAX(e.occurred_at)
                         FROM device_events e
                         WHERE e.robot_id = r.id
                           AND e.event_type = 'WALK_COMPLETED'
                       ) AS last_walk_at,
                       (
                         SELECT MAX(e.occurred_at)
                         FROM device_events e
                         WHERE e.robot_id = r.id
                           AND e.event_type = 'CALL_AND_RESPONSE'
                       ) AS last_play_at
                FROM robots r
                JOIN robot_pairings rp
                  ON rp.robot_id = r.id AND rp.unpaired_at IS NULL
                LEFT JOIN pet_affinity_states a ON a.pet_id = rp.pet_id
                LEFT JOIN robot_current_states s ON s.robot_id = r.id
                ORDER BY r.id
                """,
                (rs, rowNum) -> new RequestCandidate(
                        rs.getLong("robot_id"),
                        rs.getString("serial_number"),
                        rs.getInt("affinity_score"),
                        toInstant(rs.getTimestamp("last_interaction_at")),
                        rs.getObject("battery_level", Integer.class),
                        rs.getString("mode"),
                        toInstant(rs.getTimestamp("last_walk_at")),
                        toInstant(rs.getTimestamp("last_play_at"))
                )
        );
    }

    boolean hasOpenRequest(long robotId, BehaviorRequestType requestType) {
        Integer count = jdbcTemplate.queryForObject("""
                SELECT COUNT(*)
                FROM behavior_requests
                WHERE robot_id = ?
                  AND request_type = ?
                  AND status IN ('PENDING', 'PUBLISHED', 'RECEIVED')
                """,
                Integer.class,
                robotId,
                requestType.name()
        );
        return count != null && count > 0;
    }

    void lockRequestGeneration(long robotId) {
        jdbcTemplate.queryForObject(
                "SELECT id FROM robots WHERE id = ? FOR UPDATE",
                Long.class,
                robotId
        );
    }

    boolean hasRecentRequest(
            long robotId,
            BehaviorRequestType requestType,
            Instant createdAfter
    ) {
        Integer count = jdbcTemplate.queryForObject("""
                SELECT COUNT(*)
                FROM behavior_requests
                WHERE robot_id = ?
                  AND request_type = ?
                  AND created_at > ?
                """,
                Integer.class,
                robotId,
                requestType.name(),
                Timestamp.from(createdAfter)
        );
        return count != null && count > 0;
    }

    List<BehaviorRequestMessage> findPendingRequests(Instant now) {
        return jdbcTemplate.query("""
                SELECT b.request_id, r.serial_number, b.request_type,
                       b.message, b.created_at, b.expires_at
                FROM behavior_requests b
                JOIN robots r ON r.id = b.robot_id
                WHERE b.status = 'PENDING'
                  AND (b.expires_at IS NULL OR b.expires_at > ?)
                ORDER BY b.created_at
                """,
                (rs, rowNum) -> new BehaviorRequestMessage(
                        rs.getObject("request_id", UUID.class),
                        "1.0",
                        rs.getString("serial_number"),
                        BehaviorRequestType.valueOf(
                                rs.getString("request_type")
                        ),
                        rs.getString("message"),
                        rs.getTimestamp("created_at").toInstant(),
                        toInstant(rs.getTimestamp("expires_at"))
                ),
                Timestamp.from(now)
        );
    }

    void expireRequests(Instant now) {
        jdbcTemplate.update("""
                UPDATE behavior_requests
                SET status = 'EXPIRED'
                WHERE status IN ('PENDING', 'PUBLISHED', 'RECEIVED')
                  AND expires_at IS NOT NULL
                  AND expires_at <= ?
                """,
                Timestamp.from(now)
        );
    }

    BehaviorRequestMessage createRequest(
            RequestCandidate candidate,
            BehaviorRequestType type,
            String message,
            Instant createdAt,
            Instant expiresAt
    ) {
        UUID requestId = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO behavior_requests (
                    request_id, robot_id, request_type, status,
                    message, created_at, expires_at
                ) VALUES (?, ?, ?, 'PENDING', ?, ?, ?)
                """,
                requestId,
                candidate.robotId(),
                type.name(),
                message,
                Timestamp.from(createdAt),
                Timestamp.from(expiresAt)
        );
        return new BehaviorRequestMessage(
                requestId,
                "1.0",
                candidate.deviceId(),
                type,
                message,
                createdAt,
                expiresAt
        );
    }

    void markRequestPublished(UUID requestId, Instant publishedAt) {
        jdbcTemplate.update("""
                UPDATE behavior_requests
                SET status = 'PUBLISHED', published_at = ?
                WHERE request_id = ? AND status = 'PENDING'
                """,
                Timestamp.from(publishedAt),
                requestId
        );
    }

    private Instant toInstant(Timestamp timestamp) {
        return timestamp == null ? null : timestamp.toInstant();
    }

    record AffinityContext(
            long robotId,
            long pairingId,
            long petId,
            int currentScore
    ) {
        AffinityContext(long robotId, long petId, int currentScore) {
            this(robotId, 0L, petId, currentScore);
        }
    }

    record AffectionResult(
            String deviceId,
            UUID eventMessageId,
            int previousScore,
            int scoreChange,
            int currentScore,
            int affinityLevel,
            String mood,
            Instant occurredAt
    ) {
    }

    record RequestCandidate(
            long robotId,
            String deviceId,
            int affinityScore,
            Instant lastInteractionAt,
            Integer batteryLevel,
            String mode,
            Instant lastWalkAt,
            Instant lastPlayAt
    ) {
    }

}
