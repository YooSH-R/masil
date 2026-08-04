package com.ssafy.backend.walk;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.postgresql.PostgreSQLContainer;

import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

@Testcontainers(disabledWithoutDocker = true)
class WalkMigrationPostgreSqlTest {

    private static final Path MIGRATION = Path.of(
            "..",
            "06_Infra",
            "postgres",
            "init",
            "009_walk_api.sql"
    );

    @Container
    static final PostgreSQLContainer POSTGRES =
            new PostgreSQLContainer("postgres:17-alpine");

    @BeforeEach
    void resetSchema() throws Exception {
        try (Connection connection = openConnection();
             Statement statement = connection.createStatement()) {
            statement.execute("DROP SCHEMA public CASCADE");
            statement.execute("CREATE SCHEMA public");
            statement.execute(legacyWalkSchema());
        }
    }

    @Test
    void migratesLegacySchemaAndCanBeAppliedAgain() throws Exception {
        executeMigration();
        executeMigration();

        try (Connection connection = openConnection();
             Statement statement = connection.createStatement()) {
            assertEquals("YES", queryString(
                    statement,
                    """
                    SELECT is_nullable
                    FROM information_schema.columns
                    WHERE table_schema = 'public'
                      AND table_name = 'walks'
                      AND column_name = 'started_at'
                    """
            ));

            statement.executeUpdate(
                    "INSERT INTO robot_pairings (id) VALUES (1)"
            );
            statement.executeUpdate(
                    """
                    INSERT INTO walk_proposals (
                        robot_pairing_id, message, status,
                        proposed_at, expires_at
                    ) VALUES (
                        1, 'walk', 'PENDING',
                        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '30 minutes'
                    )
                    """
            );
            statement.executeUpdate(
                    """
                    INSERT INTO walks (
                        robot_pairing_id, proposal_id, status,
                        created_at, updated_at
                    ) VALUES (1, 1, 'READY', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                    """
            );

            SQLException duplicatePending = assertThrows(
                    SQLException.class,
                    () -> statement.executeUpdate(
                            """
                            INSERT INTO walk_proposals (
                                robot_pairing_id, message, status
                            ) VALUES (1, 'duplicate', 'PENDING')
                            """
                    )
            );
            assertEquals("23505", duplicatePending.getSQLState());

            assertEquals(
                    "walk_location_batch_requests",
                    queryString(
                            statement,
                            "SELECT to_regclass('walk_location_batch_requests')::text"
                    )
            );
        }
    }

    @Test
    void invalidLegacyDataRollsBackWholeMigration() throws Exception {
        try (Connection connection = openConnection();
             Statement statement = connection.createStatement()) {
            statement.executeUpdate(
                    "INSERT INTO robot_pairings (id) VALUES (1)"
            );
            statement.executeUpdate(
                    """
                    INSERT INTO walks (
                        robot_pairing_id, status, started_at,
                        created_at, updated_at
                    ) VALUES (
                        1, 'BROKEN', CURRENT_TIMESTAMP,
                        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
                    )
                    """
            );

            SQLException exception = assertThrows(
                    SQLException.class,
                    () -> statement.execute(Files.readString(MIGRATION))
            );
            assertTrue(exception.getMessage().contains("009_walk_api"));
            statement.execute("ROLLBACK");
        }

        try (Connection connection = openConnection();
             Statement statement = connection.createStatement()) {
            assertEquals("NO", queryString(
                    statement,
                    """
                    SELECT is_nullable
                    FROM information_schema.columns
                    WHERE table_schema = 'public'
                      AND table_name = 'walks'
                      AND column_name = 'started_at'
                    """
            ));
            assertNull(queryString(
                    statement,
                    "SELECT to_regclass('walk_location_batch_requests')::text"
            ));
        }
    }

    private void executeMigration() throws Exception {
        try (Connection connection = openConnection();
             Statement statement = connection.createStatement()) {
            statement.execute(Files.readString(MIGRATION));
        }
    }

    private Connection openConnection() throws SQLException {
        return DriverManager.getConnection(
                POSTGRES.getJdbcUrl(),
                POSTGRES.getUsername(),
                POSTGRES.getPassword()
        );
    }

    private String queryString(Statement statement, String sql)
            throws SQLException {
        try (ResultSet resultSet = statement.executeQuery(sql)) {
            resultSet.next();
            return resultSet.getString(1);
        }
    }

    private String legacyWalkSchema() {
        return """
                CREATE TABLE robot_pairings (
                    id BIGINT PRIMARY KEY
                );

                CREATE TABLE walk_proposals (
                    id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
                    robot_pairing_id BIGINT NOT NULL REFERENCES robot_pairings(id),
                    message VARCHAR(500) NOT NULL,
                    status VARCHAR(30) NOT NULL,
                    proposed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    expires_at TIMESTAMPTZ,
                    responded_at TIMESTAMPTZ
                );

                CREATE TABLE walks (
                    id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
                    robot_pairing_id BIGINT NOT NULL REFERENCES robot_pairings(id),
                    proposal_id BIGINT UNIQUE REFERENCES walk_proposals(id),
                    status VARCHAR(30) NOT NULL,
                    started_at TIMESTAMPTZ NOT NULL,
                    ended_at TIMESTAMPTZ,
                    distance_meters NUMERIC(10, 2),
                    duration_seconds INTEGER,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    CONSTRAINT walks_distance_check
                        CHECK (distance_meters IS NULL OR distance_meters >= 0),
                    CONSTRAINT walks_duration_check
                        CHECK (duration_seconds IS NULL OR duration_seconds >= 0)
                );

                CREATE TABLE walk_locations (
                    id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
                    walk_id BIGINT NOT NULL REFERENCES walks(id) ON DELETE CASCADE,
                    sequence_no INTEGER NOT NULL,
                    latitude NUMERIC(10, 7) NOT NULL,
                    longitude NUMERIC(10, 7) NOT NULL,
                    accuracy_meters NUMERIC(8, 2),
                    recorded_at TIMESTAMPTZ NOT NULL,
                    CONSTRAINT uq_walk_locations_sequence
                        UNIQUE (walk_id, sequence_no),
                    CONSTRAINT walk_locations_latitude_check
                        CHECK (latitude BETWEEN -90 AND 90),
                    CONSTRAINT walk_locations_longitude_check
                        CHECK (longitude BETWEEN -180 AND 180)
                );
                """;
    }
}
