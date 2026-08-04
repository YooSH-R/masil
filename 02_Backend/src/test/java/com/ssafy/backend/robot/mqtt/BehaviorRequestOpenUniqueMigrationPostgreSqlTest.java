package com.ssafy.backend.robot.mqtt;

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
class BehaviorRequestOpenUniqueMigrationPostgreSqlTest {

    private static final Path MIGRATION = Path.of(
            "..",
            "06_Infra",
            "postgres",
            "init",
            "010_behavior_requests_open_unique.sql"
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
            statement.execute(legacyBehaviorRequestSchema());
        }
    }

    @Test
    void createsOpenRequestIndexAndCanBeAppliedAgain() throws Exception {
        executeMigration();
        executeMigration();

        try (Connection connection = openConnection();
             Statement statement = connection.createStatement()) {
            assertEquals(
                    "idx_behavior_requests_robot_type_created",
                    queryString(
                            statement,
                            "SELECT to_regclass('idx_behavior_requests_robot_type_created')::text"
                    )
            );

            statement.executeUpdate(
                    insertRequest(1, "PLAY_REQUEST", "PENDING")
            );
            statement.executeUpdate(
                    insertRequest(1, "PLAY_REQUEST", "COMPLETED")
            );

            SQLException duplicateOpenRequest = assertThrows(
                    SQLException.class,
                    () -> statement.executeUpdate(
                            insertRequest(
                                    1,
                                    "PLAY_REQUEST",
                                    "PUBLISHED"
                            )
                    )
            );
            assertEquals("23505", duplicateOpenRequest.getSQLState());

            statement.executeUpdate(
                    insertRequest(1, "WALK_REQUEST", "RECEIVED")
            );
        }
    }

    @Test
    void duplicateLegacyRowsRollBackWholeMigration() throws Exception {
        try (Connection connection = openConnection();
             Statement statement = connection.createStatement()) {
            statement.executeUpdate(
                    insertRequest(1, "WALK_REQUEST", "PENDING")
            );
            statement.executeUpdate(
                    insertRequest(1, "WALK_REQUEST", "RECEIVED")
            );

            SQLException exception = assertThrows(
                    SQLException.class,
                    () -> statement.execute(Files.readString(MIGRATION))
            );
            assertTrue(exception.getMessage().contains(
                    "010_behavior_requests_open_unique"
            ));
            statement.execute("ROLLBACK");
        }

        try (Connection connection = openConnection();
             Statement statement = connection.createStatement()) {
            assertNull(queryString(
                    statement,
                    "SELECT to_regclass('uq_behavior_requests_open_robot_type')::text"
            ));
            assertNull(queryString(
                    statement,
                    "SELECT to_regclass('idx_behavior_requests_robot_type_created')::text"
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

    private String insertRequest(
            long robotId,
            String requestType,
            String status
    ) {
        return """
                INSERT INTO behavior_requests (
                    request_id, robot_id, request_type, status
                ) VALUES (
                    gen_random_uuid(), %d, '%s', '%s'
                )
                """.formatted(robotId, requestType, status);
    }

    private String legacyBehaviorRequestSchema() {
        return """
                CREATE TABLE behavior_requests (
                    id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
                    request_id UUID NOT NULL UNIQUE,
                    robot_id BIGINT NOT NULL,
                    request_type VARCHAR(50) NOT NULL,
                    status VARCHAR(30) NOT NULL DEFAULT 'PENDING',
                    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
                );
                """;
    }
}
