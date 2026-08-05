package com.ssafy.backend.walk.infrastructure.persistence;

import com.ssafy.backend.walk.application.WalkLocationBatchResult;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.sql.Timestamp;
import java.time.Clock;
import java.time.Instant;
import java.util.Collections;
import java.util.List;
import java.util.Optional;

@Repository
public class WalkLocationBatchRequestStore {

    private final JdbcTemplate jdbcTemplate;
    private final Clock clock;

    public WalkLocationBatchRequestStore(JdbcTemplate jdbcTemplate, Clock clock) {
        this.jdbcTemplate = jdbcTemplate;
        this.clock = clock;
    }

    public Optional<StoredBatchResult> find(Long walkId, String idempotencyKey) {
        List<StoredBatchResult> results = jdbcTemplate.query(
                """
                SELECT request_hash, received_count, saved_count, rejected_count
                FROM walk_location_batch_requests
                WHERE walk_id = ?
                  AND idempotency_key = ?
                """,
                (resultSet, rowNumber) -> new StoredBatchResult(
                        resultSet.getString("request_hash"),
                        new WalkLocationBatchResult(
                                walkId,
                                resultSet.getInt("received_count"),
                                resultSet.getInt("saved_count"),
                                resultSet.getInt("rejected_count")
                        )
                ),
                walkId,
                idempotencyKey
        );
        return results.stream().findFirst();
    }

    public void save(
            Long walkId,
            String idempotencyKey,
            String requestHash,
            WalkLocationBatchResult result
    ) {
        jdbcTemplate.update(
                """
                INSERT INTO walk_location_batch_requests (
                    walk_id,
                    idempotency_key,
                    request_hash,
                    received_count,
                    saved_count,
                    rejected_count,
                    created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                walkId,
                idempotencyKey,
                requestHash,
                result.receivedCount(),
                result.savedCount(),
                result.rejectedCount(),
                Timestamp.from(clock.instant())
        );
    }

    public int deleteCreatedBefore(Instant cutoff, int batchSize) {
        if (batchSize <= 0) {
            throw new IllegalArgumentException("batchSize must be positive");
        }

        List<Long> ids = jdbcTemplate.queryForList(
                """
                SELECT batch_request.id
                FROM walk_location_batch_requests batch_request
                JOIN walks walk_session
                  ON walk_session.id = batch_request.walk_id
                WHERE batch_request.created_at < ?
                  AND walk_session.updated_at < ?
                  AND walk_session.status IN ('COMPLETED', 'CANCELLED')
                ORDER BY batch_request.created_at, batch_request.id
                LIMIT ?
                """,
                Long.class,
                Timestamp.from(cutoff),
                Timestamp.from(cutoff),
                batchSize
        );
        if (ids.isEmpty()) {
            return 0;
        }

        String placeholders = String.join(
                ", ",
                Collections.nCopies(ids.size(), "?")
        );
        return jdbcTemplate.update(
                "DELETE FROM walk_location_batch_requests WHERE id IN ("
                        + placeholders
                        + ")",
                ids.toArray()
        );
    }

    public record StoredBatchResult(
            String requestHash,
            WalkLocationBatchResult result
    ) {
    }
}
