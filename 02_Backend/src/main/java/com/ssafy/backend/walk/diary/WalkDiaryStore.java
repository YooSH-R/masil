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

        return jdbcTemplate.query("""
                WITH owned_diaries AS (
                    SELECT w.id AS walk_id, d.walk_date, d.session_no,
                           w.started_at, w.ended_at
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
                ),
                selected_dates AS (
                    SELECT walk_date
                    FROM owned_diaries
                    GROUP BY walk_date
                    ORDER BY walk_date DESC
                    LIMIT ?
                )
                SELECT owned.walk_id, owned.walk_date, owned.session_no,
                       owned.started_at, owned.ended_at
                FROM owned_diaries owned
                JOIN selected_dates selected
                  ON selected.walk_date = owned.walk_date
                ORDER BY owned.walk_date DESC,
                         owned.session_no ASC,
                         owned.walk_id ASC
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
