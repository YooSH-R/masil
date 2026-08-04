package com.ssafy.backend.walk.diary;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

@Repository
class WalkDiaryStore {

    private final JdbcTemplate jdbcTemplate;

    WalkDiaryStore(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    Optional<StoredDiary> findOwnedDiary(long userId, long walkId) {
        return jdbcTemplate.query("""
                SELECT w.id AS walk_id, r.serial_number, d.walk_date,
                       d.session_no, d.object_prefix, w.started_at, w.ended_at
                FROM walk_diaries d
                JOIN walks w ON w.id = d.walk_id
                JOIN robot_pairings pairing
                  ON pairing.id = w.robot_pairing_id
                JOIN robots r ON r.id = pairing.robot_id
                JOIN pets pet ON pet.id = pairing.pet_id
                WHERE w.id = ?
                  AND pet.user_id = ?
                  AND pet.deleted_at IS NULL
                """,
                (rs, rowNum) -> mapDiary(rs),
                walkId,
                userId
        ).stream().findFirst();
    }

    List<FeedRow> findOwnedDiaryFeed(
            long userId,
            LocalDate beforeDate,
            int dayLimit
    ) {
        String cursorCondition = beforeDate == null
                ? ""
                : "AND d.walk_date < ?";
        List<Object> parameters = new ArrayList<>();
        parameters.add(userId);
        if (beforeDate != null) {
            parameters.add(beforeDate);
        }
        parameters.add(dayLimit);
        parameters.add(userId);

        return jdbcTemplate.query("""
                WITH selected_dates AS (
                    SELECT d.walk_date
                    FROM pets pet
                    JOIN robot_pairings pairing
                      ON pairing.pet_id = pet.id
                    JOIN walks w
                      ON w.robot_pairing_id = pairing.id
                    JOIN walk_diaries d
                      ON d.walk_id = w.id
                    WHERE pet.user_id = ?
                      AND pet.deleted_at IS NULL
                      %s
                    GROUP BY d.walk_date
                    ORDER BY d.walk_date DESC
                    LIMIT ?
                )
                SELECT w.id AS walk_id, d.walk_date, d.session_no,
                       w.started_at, w.ended_at
                FROM selected_dates selected
                JOIN walk_diaries d
                  ON d.walk_date = selected.walk_date
                JOIN walks w
                  ON w.id = d.walk_id
                JOIN robot_pairings pairing
                  ON pairing.id = w.robot_pairing_id
                JOIN pets pet
                  ON pet.id = pairing.pet_id
                WHERE pet.user_id = ?
                  AND pet.deleted_at IS NULL
                ORDER BY d.walk_date DESC, d.session_no ASC, w.id ASC
                """.formatted(cursorCondition),
                (rs, rowNum) -> mapFeedRow(rs),
                parameters.toArray()
        );
    }

    private StoredDiary mapDiary(java.sql.ResultSet rs)
            throws java.sql.SQLException {
        java.sql.Timestamp endedAt = rs.getTimestamp("ended_at");
        return new StoredDiary(
                rs.getLong("walk_id"),
                rs.getString("serial_number"),
                rs.getObject("walk_date", LocalDate.class),
                rs.getInt("session_no"),
                rs.getString("object_prefix"),
                rs.getTimestamp("started_at").toInstant(),
                endedAt == null ? null : endedAt.toInstant()
        );
    }

    private FeedRow mapFeedRow(java.sql.ResultSet rs)
            throws java.sql.SQLException {
        java.sql.Timestamp endedAt = rs.getTimestamp("ended_at");
        return new FeedRow(
                rs.getLong("walk_id"),
                rs.getObject("walk_date", LocalDate.class),
                rs.getInt("session_no"),
                rs.getTimestamp("started_at").toInstant(),
                endedAt == null ? null : endedAt.toInstant()
        );
    }

    record StoredDiary(
            long walkId,
            String deviceId,
            LocalDate walkDate,
            int session,
            String objectPrefix,
            Instant startedAt,
            Instant endedAt
    ) {
    }

    record FeedRow(
            long walkId,
            LocalDate walkDate,
            int session,
            Instant startedAt,
            Instant endedAt
    ) {
    }
}
