package com.ssafy.backend.robot.application;

import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.postgresql.PostgreSQLContainer;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

@Testcontainers
class RobotPairingMigrationPostgreSqlIntegrationTest {

    private static final Path LEGACY_SCHEMA =
            Path.of("src/test/resources/db/legacy_robot_schema.sql");
    private static final Path MIGRATION =
            Path.of("../06_Infra/postgres/migrations/002_robot_ownership.sql");

    @Container
    static final PostgreSQLContainer POSTGRES =
            new PostgreSQLContainer("postgres:17-alpine");

    @Test
    void migratesLegacyRobotSchemaAndSupportsPairingWrites() throws IOException {
        JdbcTemplate jdbcTemplate = jdbcTemplate();
        executeScript(jdbcTemplate, LEGACY_SCHEMA);
        insertLegacyData(jdbcTemplate);

        executeScript(jdbcTemplate, MIGRATION);

        assertEquals(
                1L,
                jdbcTemplate.queryForObject(
                        "SELECT owner_user_id FROM robots WHERE id = 301",
                        Long.class
                )
        );
        assertNotNull(jdbcTemplate.queryForObject(
                "SELECT updated_at FROM robots WHERE id = 301",
                Object.class
        ));
        assertEquals(
                "YES",
                columnNullable(jdbcTemplate, "robot_credentials", "qr_token_hash")
        );
        assertEquals(
                "YES",
                columnNullable(jdbcTemplate, "robot_pairings", "user_id")
        );
        assertEquals(
                7,
                jdbcTemplate.queryForObject(
                        """
                        SELECT COUNT(*)
                        FROM information_schema.columns
                        WHERE table_schema = 'public'
                          AND table_name = 'robot_credentials'
                          AND column_name IN (
                              'device_token_expires_at',
                              'device_token_rotated_at',
                              'qr_token_hash',
                              'qr_token_expires_at',
                              'qr_token_last_used_at',
                              'created_at',
                              'updated_at'
                          )
                        """,
                        Integer.class
                )
        );

        jdbcTemplate.update(
                """
                UPDATE robot_credentials
                SET qr_token_hash = ?
                WHERE robot_id = 301
                """,
                "a".repeat(64)
        );
        executeScript(jdbcTemplate, MIGRATION);

        assertEquals(
                "NO",
                columnNullable(jdbcTemplate, "robot_credentials", "qr_token_hash")
        );

        jdbcTemplate.update(
                """
                UPDATE robot_pairings
                SET unpaired_at = CURRENT_TIMESTAMP
                WHERE robot_id = 301
                """
        );
        insertProvisionedRobot(jdbcTemplate, 302L, "b".repeat(64));
        jdbcTemplate.update(
                """
                INSERT INTO robot_pairings (pet_id, robot_id)
                VALUES (201, 302)
                """
        );

        insertProvisionedRobot(jdbcTemplate, 303L, "c".repeat(64));
        assertThrows(
                DataIntegrityViolationException.class,
                () -> jdbcTemplate.update(
                        """
                        INSERT INTO robot_pairings (pet_id, robot_id)
                        VALUES (201, 303)
                        """
                )
        );
    }

    private JdbcTemplate jdbcTemplate() {
        DriverManagerDataSource dataSource = new DriverManagerDataSource(
                POSTGRES.getJdbcUrl(),
                POSTGRES.getUsername(),
                POSTGRES.getPassword()
        );
        return new JdbcTemplate(dataSource);
    }

    private void executeScript(JdbcTemplate jdbcTemplate, Path path)
            throws IOException {
        jdbcTemplate.execute(Files.readString(path));
    }

    private void insertLegacyData(JdbcTemplate jdbcTemplate) {
        jdbcTemplate.update(
                "INSERT INTO users (id, nickname) VALUES (1, 'legacy-user')"
        );
        jdbcTemplate.update(
                "INSERT INTO pets (id, user_id, name) VALUES (201, 1, 'legacy-pet')"
        );
        jdbcTemplate.update(
                """
                INSERT INTO robots (
                    id,
                    serial_number,
                    model_name,
                    firmware_version
                )
                VALUES (301, 'PETBOT-LEGACY-301', 'MYSIL-01', '0.9.0')
                """
        );
        jdbcTemplate.update(
                """
                INSERT INTO robot_credentials (
                    robot_id,
                    device_token_hash,
                    expires_at,
                    rotated_at
                )
                VALUES (
                    301,
                    'legacy-device-token',
                    CURRENT_TIMESTAMP + INTERVAL '30 days',
                    CURRENT_TIMESTAMP
                )
                """
        );
        jdbcTemplate.update(
                """
                INSERT INTO robot_pairings (user_id, pet_id, robot_id)
                VALUES (1, 201, 301)
                """
        );
    }

    private void insertProvisionedRobot(
            JdbcTemplate jdbcTemplate,
            Long robotId,
            String qrTokenHash
    ) {
        jdbcTemplate.update(
                """
                INSERT INTO robots (id, serial_number, model_name)
                VALUES (?, ?, 'MYSIL-01')
                """,
                robotId,
                "PETBOT-MIGRATED-" + robotId
        );
        jdbcTemplate.update(
                """
                INSERT INTO robot_credentials (robot_id, qr_token_hash)
                VALUES (?, ?)
                """,
                robotId,
                qrTokenHash
        );
    }

    private String columnNullable(
            JdbcTemplate jdbcTemplate,
            String tableName,
            String columnName
    ) {
        return jdbcTemplate.queryForObject(
                """
                SELECT is_nullable
                FROM information_schema.columns
                WHERE table_schema = 'public'
                  AND table_name = ?
                  AND column_name = ?
                """,
                String.class,
                tableName,
                columnName
        );
    }
}
