package com.ssafy.backend.walk;

import com.ssafy.backend.auth.service.TokenHashService;
import com.ssafy.backend.auth.service.TokenService;
import com.ssafy.backend.walk.application.WalkLocationBatchRequestCleanupScheduler;
import com.ssafy.backend.walk.infrastructure.persistence.WalkLocationBatchRequestStore;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;

import static org.hamcrest.Matchers.greaterThan;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest(properties = {
        "spring.jpa.defer-datasource-initialization=true",
        "spring.sql.init.mode=always",
        "spring.sql.init.schema-locations=classpath:walk-mqtt-test-schema.sql"
})
@AutoConfigureMockMvc
class WalkApiIntegrationTest {

    private static final long USER_ID = 91_001L;
    private static final long PET_ID = 92_001L;
    private static final long ROBOT_ID = 93_001L;
    private static final long PAIRING_ID = 94_001L;
    private static final long PROPOSAL_ID = 95_001L;
    private static final String DEVICE_TOKEN =
            "walk-device-token-with-sufficient-randomness-001";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private TokenService tokenService;

    @Autowired
    private TokenHashService tokenHashService;

    @Autowired
    private WalkLocationBatchRequestStore batchRequestStore;

    private String userToken;
    private Instant testTime;

    @BeforeEach
    void setUp() {
        clearData();
        testTime = Instant.now().truncatedTo(ChronoUnit.MILLIS);
        insertUserPetRobotAndProposal();
        userToken = tokenService.createAccessToken(USER_ID).value();
    }

    @Test
    void completesFullWalkFlowAndReturnsFrontendContract() throws Exception {
        mockMvc.perform(get("/v1/walk-proposals/current")
                        .header("Authorization", bearer(userToken)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.proposalId").value(PROPOSAL_ID))
                .andExpect(jsonPath("$.data.petId").value(PET_ID))
                .andExpect(jsonPath("$.data.robotId").value(ROBOT_ID));

        mockMvc.perform(post("/v1/walk-proposals/{id}/responses", PROPOSAL_ID)
                        .header("Authorization", bearer(userToken))
                        .header("X-Idempotency-Key", "proposal-response-" + PROPOSAL_ID)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "response": "ACCEPTED",
                                  "respondedAt": "%s"
                                }
                                """.formatted(testTime)))
                .andExpect(status().isNoContent());

        mockMvc.perform(post("/v1/walk-proposals/{id}/responses", PROPOSAL_ID)
                        .header("Authorization", bearer(userToken))
                        .header("X-Idempotency-Key", "proposal-response-" + PROPOSAL_ID)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "response": "ACCEPTED",
                                  "respondedAt": "%s"
                                }
                                """.formatted(testTime)))
                .andExpect(status().isNoContent());

        mockMvc.perform(post("/v1/walks")
                        .header("Authorization", bearer(userToken))
                        .header("X-Idempotency-Key", "create-walk-" + PROPOSAL_ID)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "proposalId": %d,
                                  "petId": %d,
                                  "robotId": %d
                                }
                                """.formatted(PROPOSAL_ID, PET_ID, ROBOT_ID)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.data.status").value("READY"));

        mockMvc.perform(post("/v1/walks")
                        .header("Authorization", bearer(userToken))
                        .header("X-Idempotency-Key", "create-walk-" + PROPOSAL_ID)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "proposalId": %d,
                                  "petId": %d,
                                  "robotId": %d
                                }
                                """.formatted(PROPOSAL_ID, PET_ID, ROBOT_ID)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.data.status").value("READY"));

        Long walkId = jdbcTemplate.queryForObject(
                "SELECT id FROM walks WHERE proposal_id = ?",
                Long.class,
                PROPOSAL_ID
        );
        Instant startedAt = Instant.now().truncatedTo(ChronoUnit.MILLIS);
        mockMvc.perform(post("/v1/walks/{id}/start", walkId)
                        .header("Authorization", "Device " + DEVICE_TOKEN)
                        .header("X-Idempotency-Key", "walk-start-1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"startedAt": "%s"}
                                """.formatted(startedAt)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("ACTIVE"));

        mockMvc.perform(post("/v1/walks/{id}/start", walkId)
                        .header("Authorization", "Device " + DEVICE_TOKEN)
                        .header("X-Idempotency-Key", "walk-start-1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"startedAt": "%s"}
                                """.formatted(startedAt)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("ACTIVE"));

        Instant firstRecordedAt = startedAt.plusSeconds(1);
        String batchBody = """
                {
                  "points": [
                    {
                      "latitude": 37.0000000,
                      "longitude": 127.0000000,
                      "accuracy": 5.0,
                      "sequence": 0,
                      "recordedAt": "%s"
                    },
                    {
                      "latitude": 37.0010000,
                      "longitude": 127.0000000,
                      "accuracy": 8.0,
                      "sequence": 1,
                      "recordedAt": "%s"
                    },
                    {
                      "latitude": 37.0020000,
                      "longitude": 127.0000000,
                      "accuracy": 51.0,
                      "sequence": 2,
                      "recordedAt": "%s"
                    }
                  ]
                }
                """.formatted(
                firstRecordedAt,
                firstRecordedAt.plusSeconds(5),
                firstRecordedAt.plusSeconds(10)
        );
        mockMvc.perform(post("/v1/walks/{id}/locations/batch", walkId)
                        .header("Authorization", bearer(userToken))
                        .header("X-Idempotency-Key", "walk-location-batch-1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(batchBody))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.receivedCount").value(3))
                .andExpect(jsonPath("$.data.savedCount").value(2))
                .andExpect(jsonPath("$.data.rejectedCount").value(1));

        mockMvc.perform(post("/v1/walks/{id}/locations/batch", walkId)
                        .header("Authorization", bearer(userToken))
                        .header("X-Idempotency-Key", "walk-location-conflict")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "points": [{
                                    "latitude": 38.0010000,
                                    "longitude": 127.0000000,
                                    "accuracy": 8.0,
                                    "sequence": 1,
                                    "recordedAt": "%s"
                                  }]
                                }
                                """.formatted(firstRecordedAt.plusSeconds(5))))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error.code")
                        .value("WALK_LOCATION_SEQUENCE_CONFLICT"));

        mockMvc.perform(post("/v1/walks/{id}/locations/batch", walkId)
                        .header("Authorization", bearer(userToken))
                        .header("X-Idempotency-Key", "walk-location-batch-1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "points": [{
                                    "latitude": 37.0030000,
                                    "longitude": 127.0000000,
                                    "accuracy": 8.0,
                                    "sequence": 3,
                                    "recordedAt": "%s"
                                  }]
                                }
                                """.formatted(firstRecordedAt.plusSeconds(15))))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error.code")
                        .value("IDEMPOTENCY_KEY_REUSED"));

        mockMvc.perform(post("/v1/walks/{id}/locations/batch", walkId)
                        .header("Authorization", bearer(userToken))
                        .header("X-Idempotency-Key", "walk-location-batch-1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(batchBody))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.savedCount").value(2))
                .andExpect(jsonPath("$.data.rejectedCount").value(1));

        Instant endedAt = firstRecordedAt.plusSeconds(20);
        mockMvc.perform(post("/v1/walks/{id}/end", walkId)
                        .header("Authorization", "Device " + DEVICE_TOKEN)
                        .header("X-Idempotency-Key", "walk-end-1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"endedAt": "%s"}
                                """.formatted(endedAt)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("COMPLETED"))
                .andExpect(jsonPath("$.data.distanceMeters", greaterThan(100)));

        assertEquals(10, jdbcTemplate.queryForObject(
                "SELECT affinity_score FROM pet_affinity_states WHERE pet_id = ?",
                Integer.class,
                PET_ID
        ));
        assertEquals(1, jdbcTemplate.queryForObject(
                """
                SELECT COUNT(*)
                FROM device_events
                WHERE robot_id = ? AND event_type = 'WALK_COMPLETED'
                """,
                Integer.class,
                ROBOT_ID
        ));

        mockMvc.perform(post("/v1/walks/{id}/locations/batch", walkId)
                        .header("Authorization", bearer(userToken))
                        .header("X-Idempotency-Key", "walk-location-final")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "points": [{
                                    "latitude": 37.0020000,
                                    "longitude": 127.0000000,
                                    "accuracy": 7.0,
                                    "sequence": 2,
                                    "recordedAt": "%s"
                                  }]
                                }
                                """.formatted(endedAt.minusSeconds(1))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.savedCount").value(1));

        mockMvc.perform(post("/v1/walks/{id}/end", walkId)
                        .header("Authorization", "Device " + DEVICE_TOKEN)
                        .header("X-Idempotency-Key", "walk-end-1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"endedAt": "%s"}
                                """.formatted(endedAt)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("COMPLETED"));

        assertEquals(10, jdbcTemplate.queryForObject(
                "SELECT affinity_score FROM pet_affinity_states WHERE pet_id = ?",
                Integer.class,
                PET_ID
        ));
        assertEquals(1, jdbcTemplate.queryForObject(
                """
                SELECT COUNT(*)
                FROM device_events
                WHERE robot_id = ? AND event_type = 'WALK_COMPLETED'
                """,
                Integer.class,
                ROBOT_ID
        ));

        mockMvc.perform(get("/v1/walks/{id}/summary", walkId)
                        .header("Authorization", bearer(userToken)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.route.length()").value(3))
                .andExpect(jsonPath("$.data.route[0].sequence").value(0))
                .andExpect(jsonPath("$.data.route[1].sequence").value(1))
                .andExpect(jsonPath("$.data.route[2].sequence").value(2))
                .andExpect(jsonPath("$.data.distanceMeters", greaterThan(200)));

        mockMvc.perform(get("/v1/walks")
                        .header("Authorization", bearer(userToken))
                        .param("limit", "20"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items.length()").value(1))
                .andExpect(jsonPath("$.data.items[0].walkId").value(walkId))
                .andExpect(jsonPath("$.data.hasNext").value(false));
    }

    @Test
    void returnsNoContentWhenCurrentProposalDoesNotExist() throws Exception {
        jdbcTemplate.update("DELETE FROM walk_proposals");

        mockMvc.perform(get("/v1/walk-proposals/current")
                        .header("Authorization", bearer(userToken)))
                .andExpect(status().isNoContent());
    }

    @Test
    void expiresStaleCurrentProposalAndReleasesPendingSlot() throws Exception {
        jdbcTemplate.update(
                "UPDATE walk_proposals SET expires_at = ? WHERE id = ?",
                testTime.minusSeconds(1),
                PROPOSAL_ID
        );

        mockMvc.perform(get("/v1/walk-proposals/current")
                        .header("Authorization", bearer(userToken)))
                .andExpect(status().isNoContent());

        String status = jdbcTemplate.queryForObject(
                "SELECT status FROM walk_proposals WHERE id = ?",
                String.class,
                PROPOSAL_ID
        );
        assertEquals("EXPIRED", status);
    }

    @Test
    void returnsExpiredErrorForInitialAndRetriedExpiredProposalResponse()
            throws Exception {
        jdbcTemplate.update(
                "UPDATE walk_proposals SET expires_at = ? WHERE id = ?",
                testTime.minusSeconds(1),
                PROPOSAL_ID
        );
        String requestBody = """
                {
                  "response": "ACCEPTED",
                  "respondedAt": "%s"
                }
                """.formatted(testTime);

        for (int attempt = 0; attempt < 2; attempt++) {
            mockMvc.perform(post(
                            "/v1/walk-proposals/{id}/responses",
                            PROPOSAL_ID
                    )
                            .header("Authorization", bearer(userToken))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(requestBody))
                    .andExpect(status().isConflict())
                    .andExpect(jsonPath("$.error.code")
                            .value("WALK_PROPOSAL_EXPIRED"));
        }

        String proposalStatus = jdbcTemplate.queryForObject(
                "SELECT status FROM walk_proposals WHERE id = ?",
                String.class,
                PROPOSAL_ID
        );
        assertEquals("EXPIRED", proposalStatus);
    }

    @Test
    void deletesExpiredLocationBatchRequestsInBoundedBatches()
            throws Exception {
        acceptProposalAndCreateWalk();
        Long walkId = jdbcTemplate.queryForObject(
                "SELECT id FROM walks WHERE proposal_id = ?",
                Long.class,
                PROPOSAL_ID
        );
        for (int daysAgo : new int[]{10, 9, 8, 1}) {
            jdbcTemplate.update(
                    """
                    INSERT INTO walk_location_batch_requests (
                        walk_id, idempotency_key, request_hash,
                        received_count, saved_count, rejected_count, created_at
                    ) VALUES (?, ?, ?, 0, 0, 0, ?)
                    """,
                    walkId,
                    "retention-test-" + daysAgo,
                    "0".repeat(64),
                    testTime.minus(daysAgo, ChronoUnit.DAYS)
            );
        }

        WalkLocationBatchRequestCleanupScheduler scheduler =
                new WalkLocationBatchRequestCleanupScheduler(
                        batchRequestStore,
                        Clock.fixed(testTime, ZoneOffset.UTC),
                        7 * 24 * 60 * 60,
                        2
                );

        assertEquals(0, scheduler.deleteExpiredBatchRequests());
        jdbcTemplate.update(
                """
                UPDATE walks
                SET status = 'CANCELLED', updated_at = ?
                WHERE id = ?
                """,
                testTime.minus(8, ChronoUnit.DAYS),
                walkId
        );
        assertEquals(2, scheduler.deleteExpiredBatchRequests());
        assertEquals(
                2,
                jdbcTemplate.queryForObject(
                        "SELECT COUNT(*) FROM walk_location_batch_requests",
                        Integer.class
                )
        );
        assertEquals(1, scheduler.deleteExpiredBatchRequests());
        assertEquals(
                1,
                jdbcTemplate.queryForObject(
                        "SELECT COUNT(*) FROM walk_location_batch_requests",
                        Integer.class
                )
        );
    }

    @Test
    void rejectsUserTokenForDeviceEndpointAndDeviceTokenForUserEndpoint()
            throws Exception {
        acceptProposalAndCreateWalk();
        Long walkId = jdbcTemplate.queryForObject(
                "SELECT id FROM walks WHERE proposal_id = ?",
                Long.class,
                PROPOSAL_ID
        );

        mockMvc.perform(post("/v1/walks/{id}/start", walkId)
                        .header("Authorization", bearer(userToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"startedAt": "%s"}
                                """.formatted(Instant.now())))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.error.code").value("INVALID_DEVICE_TOKEN"))
                .andExpect(jsonPath("$.error.details").isMap())
                .andExpect(jsonPath("$.traceId").isNotEmpty())
                .andExpect(jsonPath("$.timestamp").isNotEmpty());

        jdbcTemplate.update(
                """
                UPDATE robot_credentials
                SET device_token_expires_at = ?
                WHERE robot_id = ?
                """,
                Instant.now().minusSeconds(1),
                ROBOT_ID
        );
        mockMvc.perform(post("/v1/walks/{id}/start", walkId)
                        .header("Authorization", "Device " + DEVICE_TOKEN)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"startedAt": "%s"}
                                """.formatted(Instant.now())))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.error.code").value("INVALID_DEVICE_TOKEN"))
                .andExpect(jsonPath("$.traceId").isNotEmpty())
                .andExpect(jsonPath("$.timestamp").isNotEmpty());

        mockMvc.perform(get("/v1/walks")
                        .header("Authorization", "Device " + DEVICE_TOKEN))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.error.code").value("AUTHENTICATION_REQUIRED"))
                .andExpect(jsonPath("$.traceId").isNotEmpty())
                .andExpect(jsonPath("$.timestamp").isNotEmpty());

        mockMvc.perform(get("/v1/walks")
                        .header("Authorization", "Bearer invalid-access-token"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.error.code").value("AUTHENTICATION_REQUIRED"));

        mockMvc.perform(get("/v1/walks"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.error.code").value("AUTHENTICATION_REQUIRED"));
    }

    @Test
    void hidesWalkOwnedByAnotherUser() throws Exception {
        acceptProposalAndCreateWalk();
        Long walkId = jdbcTemplate.queryForObject(
                "SELECT id FROM walks WHERE proposal_id = ?",
                Long.class,
                PROPOSAL_ID
        );
        jdbcTemplate.update(
                """
                INSERT INTO users (id, version, nickname, created_at, updated_at)
                VALUES (?, 0, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """,
                USER_ID + 1,
                "other-walk-user"
        );
        String otherToken = tokenService.createAccessToken(USER_ID + 1).value();

        mockMvc.perform(get("/v1/walks/{id}", walkId)
                        .header("Authorization", bearer(otherToken)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("WALK_NOT_FOUND"));
    }

    private void acceptProposalAndCreateWalk() throws Exception {
        jdbcTemplate.update(
                """
                UPDATE walk_proposals
                SET status = 'ACCEPTED', responded_at = CURRENT_TIMESTAMP
                WHERE id = ?
                """,
                PROPOSAL_ID
        );
        mockMvc.perform(post("/v1/walks")
                        .header("Authorization", bearer(userToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "proposalId": %d,
                                  "petId": %d,
                                  "robotId": %d
                                }
                                """.formatted(PROPOSAL_ID, PET_ID, ROBOT_ID)))
                .andExpect(status().isCreated());
    }

    private void insertUserPetRobotAndProposal() {
        jdbcTemplate.update(
                """
                INSERT INTO users (id, version, nickname, created_at, updated_at)
                VALUES (?, 0, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """,
                USER_ID,
                "walk-api-user"
        );
        jdbcTemplate.update(
                """
                INSERT INTO pets (id, user_id, name, created_at, updated_at)
                VALUES (?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """,
                PET_ID,
                USER_ID,
                "walk-api-pet"
        );
        jdbcTemplate.update(
                """
                INSERT INTO pet_affinity_states (
                    pet_id, affinity_score, affinity_level, mood, updated_at
                ) VALUES (?, 0, 1, 'NEUTRAL', CURRENT_TIMESTAMP)
                """,
                PET_ID
        );
        jdbcTemplate.update(
                """
                INSERT INTO robots (
                    id, serial_number, model_name, owner_user_id,
                    ownership_claimed_at, updated_at
                ) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """,
                ROBOT_ID,
                "WALK-DEVICE-001",
                "MYSIL-WALK",
                USER_ID
        );
        jdbcTemplate.update(
                """
                INSERT INTO robot_credentials (
                    robot_id, device_token_hash, qr_token_hash, updated_at
                ) VALUES (?, ?, ?, CURRENT_TIMESTAMP)
                """,
                ROBOT_ID,
                tokenHashService.hash(DEVICE_TOKEN),
                tokenHashService.hash("walk-qr-token-001")
        );
        jdbcTemplate.update(
                """
                INSERT INTO robot_pairings (id, pet_id, robot_id, paired_at)
                VALUES (?, ?, ?, CURRENT_TIMESTAMP)
                """,
                PAIRING_ID,
                PET_ID,
                ROBOT_ID
        );
        jdbcTemplate.update(
                """
                INSERT INTO walk_proposals (
                    id, robot_pairing_id, message, status, proposed_at, expires_at
                ) VALUES (?, ?, ?, 'PENDING', ?, ?)
                """,
                PROPOSAL_ID,
                PAIRING_ID,
                "산책하러 갈까요?",
                testTime.minusSeconds(60),
                testTime.plusSeconds(3600)
        );
    }

    private void clearData() {
        jdbcTemplate.execute("SET REFERENTIAL_INTEGRITY FALSE");
        for (String table : new String[]{
                "walk_location_batch_requests",
                "walk_locations",
                "walks",
                "walk_proposals",
                "device_events",
                "robot_pairings",
                "robot_credentials",
                "robots",
                "pet_affinity_states",
                "pets",
                "users"
        }) {
            jdbcTemplate.execute("TRUNCATE TABLE " + table);
        }
        jdbcTemplate.execute("SET REFERENTIAL_INTEGRITY TRUE");
    }

    private String bearer(String token) {
        return "Bearer " + token;
    }
}
