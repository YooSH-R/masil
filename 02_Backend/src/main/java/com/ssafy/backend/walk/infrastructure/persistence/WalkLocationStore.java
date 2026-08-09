package com.ssafy.backend.walk.infrastructure.persistence;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@Repository
public class WalkLocationStore {

    private final JdbcTemplate jdbcTemplate;
    private final NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    public WalkLocationStore(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
        this.namedParameterJdbcTemplate = new NamedParameterJdbcTemplate(jdbcTemplate);
    }

    public Map<Integer, Point> findBySequences(
            Long walkId,
            Collection<Integer> sequences
    ) {
        if (sequences.isEmpty()) {
            return Map.of();
        }
        MapSqlParameterSource parameters = new MapSqlParameterSource()
                .addValue("walkId", walkId)
                .addValue("sequences", sequences);
        Map<Integer, Point> result = new LinkedHashMap<>();
        namedParameterJdbcTemplate.query(
                """
                SELECT sequence_no, latitude, longitude, accuracy_meters, recorded_at
                FROM walk_locations
                WHERE walk_id = :walkId
                  AND sequence_no IN (:sequences)
                """,
                parameters,
                resultSet -> {
                    Point point = mapPoint(resultSet);
                    result.put(point.sequence(), point);
                }
        );
        return result;
    }

    public void insertBatch(Long walkId, List<Point> points) {
        jdbcTemplate.batchUpdate(
                """
                INSERT INTO walk_locations (
                    walk_id,
                    sequence_no,
                    latitude,
                    longitude,
                    accuracy_meters,
                    recorded_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                points,
                100,
                (statement, point) -> {
                    statement.setLong(1, walkId);
                    statement.setInt(2, point.sequence());
                    statement.setBigDecimal(3, point.latitude());
                    statement.setBigDecimal(4, point.longitude());
                    statement.setBigDecimal(5, point.accuracy());
                    statement.setTimestamp(6, Timestamp.from(point.recordedAt()));
                }
        );
    }

    public List<Point> findAll(Long walkId) {
        return jdbcTemplate.query(
                """
                SELECT sequence_no, latitude, longitude, accuracy_meters, recorded_at
                FROM walk_locations
                WHERE walk_id = ?
                ORDER BY sequence_no ASC
                """,
                (resultSet, rowNumber) -> mapPoint(resultSet),
                walkId
        );
    }

    public Optional<Instant> findLatestRecordedAt(Long walkId) {
        return Optional.ofNullable(jdbcTemplate.queryForObject(
                "SELECT MAX(recorded_at) FROM walk_locations WHERE walk_id = ?",
                Timestamp.class,
                walkId
        )).map(Timestamp::toInstant);
    }

    private Point mapPoint(java.sql.ResultSet resultSet) throws java.sql.SQLException {
        return new Point(
                resultSet.getBigDecimal("latitude"),
                resultSet.getBigDecimal("longitude"),
                resultSet.getBigDecimal("accuracy_meters"),
                resultSet.getInt("sequence_no"),
                resultSet.getTimestamp("recorded_at").toInstant()
        );
    }

    public record Point(
            BigDecimal latitude,
            BigDecimal longitude,
            BigDecimal accuracy,
            Integer sequence,
            Instant recordedAt
    ) {
        public boolean hasSamePayload(Point other) {
            return latitude.compareTo(other.latitude) == 0
                    && longitude.compareTo(other.longitude) == 0
                    && sameNullableDecimal(accuracy, other.accuracy)
                    && recordedAt.equals(other.recordedAt);
        }

        private boolean sameNullableDecimal(BigDecimal first, BigDecimal second) {
            if (first == null || second == null) {
                return first == second;
            }
            return first.compareTo(second) == 0;
        }
    }
}
