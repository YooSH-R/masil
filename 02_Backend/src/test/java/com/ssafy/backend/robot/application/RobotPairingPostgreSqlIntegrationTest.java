package com.ssafy.backend.robot.application;

import com.ssafy.backend.auth.service.TokenHashService;
import com.ssafy.backend.auth.service.TokenService;
import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.postgresql.PostgreSQLContainer;

import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@Testcontainers(disabledWithoutDocker = true)
@AutoConfigureMockMvc
@SpringBootTest(properties = {
        "spring.jpa.hibernate.ddl-auto=validate",
        "spring.sql.init.mode=always",
        "spring.sql.init.schema-locations=file:../06_Infra/postgres/init/001_schema.sql",
        "solapi.api-key=test-api-key",
        "solapi.secret-key=test-secret-key",
        "solapi.sender=01000000000"
})
class RobotPairingPostgreSqlIntegrationTest {

    private static final String QR_TOKEN =
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";

    @Container
    @ServiceConnection
    static final PostgreSQLContainer POSTGRES =
            new PostgreSQLContainer("postgres:17-alpine");

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private RobotPairingService pairingService;

    @Autowired
    private TokenHashService tokenHashService;

    @Autowired
    private TokenService tokenService;

    @Autowired
    private MockMvc mockMvc;

    @BeforeEach
    void resetData() {
        jdbcTemplate.execute(
                "TRUNCATE TABLE users, robots RESTART IDENTITY CASCADE"
        );
    }

    @Test
    void persistsPairingOwnershipAndQrAuditTime() {
        insertUserAndPet(1L, 201L);
        insertRobot(301L, QR_TOKEN);

        RobotPairingResult result = pairingService.pair(1L, 201L, QR_TOKEN);

        assertNotNull(result.pairingId());
        assertEquals(301L, result.robotId());
        assertEquals(
                1L,
                jdbcTemplate.queryForObject(
                        "SELECT owner_user_id FROM robots WHERE id = 301",
                        Long.class
                )
        );
        assertNotNull(jdbcTemplate.queryForObject(
                """
                SELECT qr_token_last_used_at
                FROM robot_credentials
                WHERE robot_id = 301
                """,
                Object.class
        ));
    }

    @Test
    void authenticatedHttpRequestCreatesPairing() throws Exception {
        insertUserAndPet(1L, 201L);
        insertRobot(301L, QR_TOKEN);
        String accessToken = tokenService.createAccessToken(1L).value();

        mockMvc.perform(post("/v1/robots/pairings")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "petId": 201,
                                  "qrToken": "%s"
                                }
                                """.formatted(QR_TOKEN)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.robotId").value(301))
                .andExpect(jsonPath("$.data.petId").value(201))
                .andExpect(jsonPath("$.data.pairingStatus").value("PAIRED"));
    }

    @Test
    void unauthenticatedHttpRequestIsRejected() throws Exception {
        mockMvc.perform(post("/v1/robots/pairings")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "petId": 201,
                                  "qrToken": "%s"
                                }
                                """.formatted(QR_TOKEN)))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void repeatedRequestReturnsExistingPairingWithoutDuplicateRow() {
        insertUserAndPet(1L, 201L);
        insertRobot(301L, QR_TOKEN);

        RobotPairingResult first = pairingService.pair(1L, 201L, QR_TOKEN);
        RobotPairingResult second = pairingService.pair(1L, 201L, QR_TOKEN);

        assertEquals(first.pairingId(), second.pairingId());
        assertEquals(
                1,
                jdbcTemplate.queryForObject(
                        "SELECT COUNT(*) FROM robot_pairings",
                        Integer.class
                )
        );
    }

    @Test
    void copiedQrCannotBeClaimedAfterOriginalOwnerUnpairs() {
        insertUserAndPet(1L, 201L);
        insertUserAndPet(2L, 202L);
        insertRobot(301L, QR_TOKEN);
        RobotPairingResult pairing = pairingService.pair(1L, 201L, QR_TOKEN);
        jdbcTemplate.update(
                """
                UPDATE robot_pairings
                SET unpaired_at = CURRENT_TIMESTAMP
                WHERE id = ?
                """,
                pairing.pairingId()
        );

        BusinessException exception = assertThrows(
                BusinessException.class,
                () -> pairingService.pair(2L, 202L, QR_TOKEN)
        );

        assertEquals(
                ErrorCode.ROBOT_OWNERSHIP_MISMATCH,
                exception.errorCode()
        );
    }

    @Test
    void concurrentRequestsCreateOnlyOneActivePairingForRobot() throws Exception {
        insertUserAndPet(1L, 201L);
        insertPet(202L, 1L);
        insertRobot(301L, QR_TOKEN);
        CountDownLatch start = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(2);

        try {
            List<Future<RobotPairingResult>> futures = List.of(
                    executor.submit(() -> {
                        start.await();
                        return pairingService.pair(1L, 201L, QR_TOKEN);
                    }),
                    executor.submit(() -> {
                        start.await();
                        return pairingService.pair(1L, 202L, QR_TOKEN);
                    })
            );
            start.countDown();

            int successes = 0;
            int conflicts = 0;
            for (Future<RobotPairingResult> future : futures) {
                try {
                    future.get();
                    successes++;
                } catch (ExecutionException exception) {
                    Throwable cause = exception.getCause();
                    assertTrue(cause instanceof BusinessException);
                    assertEquals(
                            ErrorCode.ROBOT_ALREADY_PAIRED,
                            ((BusinessException) cause).errorCode()
                    );
                    conflicts++;
                }
            }

            assertEquals(1, successes);
            assertEquals(1, conflicts);
        } finally {
            executor.shutdownNow();
        }

        assertEquals(
                1,
                jdbcTemplate.queryForObject(
                        """
                        SELECT COUNT(*)
                        FROM robot_pairings
                        WHERE robot_id = 301
                          AND unpaired_at IS NULL
                        """,
                        Integer.class
                )
        );
    }

    private void insertUserAndPet(Long userId, Long petId) {
        jdbcTemplate.update(
                """
                INSERT INTO users (id, nickname)
                VALUES (?, ?)
                """,
                userId,
                "user-" + userId
        );
        insertPet(petId, userId);
    }

    private void insertPet(Long petId, Long userId) {
        jdbcTemplate.update(
                """
                INSERT INTO pets (id, user_id, name)
                VALUES (?, ?, ?)
                """,
                petId,
                userId,
                "pet-" + petId
        );
    }

    private void insertRobot(Long robotId, String qrToken) {
        jdbcTemplate.update(
                """
                INSERT INTO robots (
                    id,
                    serial_number,
                    model_name,
                    firmware_version
                )
                VALUES (?, ?, ?, ?)
                """,
                robotId,
                "PETBOT-" + robotId,
                "MYSIL-01",
                "1.0.0"
        );
        jdbcTemplate.update(
                """
                INSERT INTO robot_credentials (
                    robot_id,
                    qr_token_hash
                )
                VALUES (?, ?)
                """,
                robotId,
                tokenHashService.hash(qrToken)
        );
    }
}
