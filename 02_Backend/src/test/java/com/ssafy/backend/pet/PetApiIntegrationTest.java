package com.ssafy.backend.pet;

import com.ssafy.backend.auth.service.TokenService;
import com.ssafy.backend.pet.application.PetCreatedResult;
import com.ssafy.backend.pet.application.PetService;
import com.ssafy.backend.user.infrastructure.persistence.SpringDataUserRepository;
import com.ssafy.backend.user.infrastructure.persistence.UserJpaEntity;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@AutoConfigureMockMvc
@SpringBootTest(properties = {
        "solapi.api-key=test-api-key",
        "solapi.secret-key=test-secret-key",
        "solapi.sender=01000000000"
})
class PetApiIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private SpringDataUserRepository userRepository;

    @Autowired
    private TokenService tokenService;

    @Autowired
    private PetService petService;

    @BeforeEach
    void resetData() {
        jdbcTemplate.execute("DELETE FROM robot_current_states");
        jdbcTemplate.execute("DELETE FROM robot_pairings");
        jdbcTemplate.execute("DELETE FROM robot_credentials");
        jdbcTemplate.execute("DELETE FROM robots");
        jdbcTemplate.execute("DELETE FROM pet_creation_requests");
        jdbcTemplate.execute("DELETE FROM pet_affinity_states");
        jdbcTemplate.execute("DELETE FROM pets");
        jdbcTemplate.execute("DELETE FROM auth_sessions");
        jdbcTemplate.execute("DELETE FROM social_accounts");
        jdbcTemplate.execute("DELETE FROM social_signup_tickets");
        jdbcTemplate.execute("DELETE FROM auth_verifications");
        jdbcTemplate.execute("DELETE FROM users");
    }

    @Test
    void createsPetWithInitialAffinityAndHandlesRepeatedRequest()
            throws Exception {
        UserJpaEntity user = saveUser("owner@example.com", "주인");
        String bearer = bearer(user);

        mockMvc.perform(post("/v1/pets")
                        .header("Authorization", bearer)
                        .header("X-Idempotency-Key", "create-pet-001")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "몽이",
                                  "profileImage": null
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.name").value("몽이"))
                .andExpect(jsonPath("$.data.affinity.score").value(0))
                .andExpect(jsonPath("$.data.affinity.level").value(1))
                .andExpect(jsonPath("$.data.affinity.mood")
                        .value("NEUTRAL"));

        mockMvc.perform(post("/v1/pets")
                        .header("Authorization", bearer)
                        .header("X-Idempotency-Key", "create-pet-001")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "몽이",
                                  "profileImage": null
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.data.name").value("몽이"));

        assertEquals(
                1,
                jdbcTemplate.queryForObject(
                        "SELECT COUNT(*) FROM pets",
                        Integer.class
                )
        );
        assertEquals(
                1,
                jdbcTemplate.queryForObject(
                        "SELECT COUNT(*) FROM pet_affinity_states",
                        Integer.class
                )
        );
    }

    @Test
    void returnsSamePetForConcurrentRequestsWithSameIdempotencyKey()
            throws Exception {
        UserJpaEntity user = saveUser("owner@example.com", "주인");
        ExecutorService executor = Executors.newFixedThreadPool(2);
        CountDownLatch ready = new CountDownLatch(2);
        CountDownLatch start = new CountDownLatch(1);

        try {
            Future<PetCreatedResult> first = executor.submit(() -> {
                ready.countDown();
                start.await();
                return petService.create(
                        user.getId(),
                        "concurrent-create",
                        "몽이"
                );
            });
            Future<PetCreatedResult> second = executor.submit(() -> {
                ready.countDown();
                start.await();
                return petService.create(
                        user.getId(),
                        "concurrent-create",
                        "몽이"
                );
            });

            assertTrue(ready.await(5, TimeUnit.SECONDS));
            start.countDown();

            PetCreatedResult firstResult =
                    first.get(10, TimeUnit.SECONDS);
            PetCreatedResult secondResult =
                    second.get(10, TimeUnit.SECONDS);

            assertEquals(firstResult.petId(), secondResult.petId());
            assertEquals(
                    1,
                    jdbcTemplate.queryForObject(
                            "SELECT COUNT(*) FROM pets",
                            Integer.class
                    )
            );
            assertEquals(
                    1,
                    jdbcTemplate.queryForObject(
                            "SELECT COUNT(*) FROM pet_creation_requests",
                            Integer.class
                    )
            );
        } finally {
            start.countDown();
            executor.shutdownNow();
        }
    }

    @Test
    void rejectsSameIdempotencyKeyWithDifferentRequest() throws Exception {
        UserJpaEntity user = saveUser("owner@example.com", "주인");
        String bearer = bearer(user);

        createPet(bearer, "same-key", "몽이");

        mockMvc.perform(post("/v1/pets")
                        .header("Authorization", bearer)
                        .header("X-Idempotency-Key", "same-key")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "초코",
                                  "profileImage": null
                                }
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code")
                        .value("INVALID_REQUEST"));
    }

    @Test
    void getsProfileWithAffinityAndActiveRobotState() throws Exception {
        UserJpaEntity user = saveUser("owner@example.com", "주인");
        PetCreatedResult pet = petService.create(
                user.getId(),
                "setup-pet",
                "몽이"
        );
        insertRobotState(pet.petId(), 301L);

        mockMvc.perform(get("/v1/pets/{petId}", pet.petId())
                        .header("Authorization", bearer(user)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.petId").value(pet.petId()))
                .andExpect(jsonPath("$.data.name").value("몽이"))
                .andExpect(jsonPath("$.data.profileImageUrl").doesNotExist())
                .andExpect(jsonPath("$.data.affinity.mood")
                        .value("NEUTRAL"))
                .andExpect(jsonPath("$.data.robot.robotId").value(301))
                .andExpect(jsonPath("$.data.robot.online").value(true))
                .andExpect(jsonPath("$.data.robot.batteryLevel").value(82));
    }

    @Test
    void returnsNotFoundWhenAnotherUserRequestsPet() throws Exception {
        UserJpaEntity owner = saveUser("owner@example.com", "주인");
        UserJpaEntity other = saveUser("other@example.com", "다른사용자");
        PetCreatedResult pet = petService.create(
                owner.getId(),
                "owner-pet",
                "몽이"
        );

        mockMvc.perform(get("/v1/pets/{petId}", pet.petId())
                        .header("Authorization", bearer(other)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code")
                        .value("PET_NOT_FOUND"));
    }

    @Test
    void reportsDataIntegrityErrorWhenAffinityStateIsMissing()
            throws Exception {
        UserJpaEntity user = saveUser("owner@example.com", "주인");
        PetCreatedResult pet = petService.create(
                user.getId(),
                "missing-affinity",
                "몽이"
        );
        jdbcTemplate.update(
                "DELETE FROM pet_affinity_states WHERE pet_id = ?",
                pet.petId()
        );

        mockMvc.perform(get("/v1/pets/{petId}", pet.petId())
                        .header("Authorization", bearer(user)))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.error.code")
                        .value("PET_AFFINITY_STATE_NOT_FOUND"));
    }

    @Test
    void updatesPetNameAndRejectsProfileImageUpload() throws Exception {
        UserJpaEntity user = saveUser("owner@example.com", "주인");
        PetCreatedResult pet = petService.create(
                user.getId(),
                "update-pet",
                "몽이"
        );
        String bearer = bearer(user);

        mockMvc.perform(patch("/v1/pets/{petId}", pet.petId())
                        .header("Authorization", bearer)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "초코",
                                  "profileImage": null
                                }
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.name").value("초코"));

        mockMvc.perform(patch("/v1/pets/{petId}", pet.petId())
                        .header("Authorization", bearer)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "초코",
                                  "profileImage": "base64-image"
                                }
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code")
                        .value("INVALID_REQUEST"));
    }

    private UserJpaEntity saveUser(String email, String nickname) {
        return userRepository.saveAndFlush(new UserJpaEntity(
                email,
                null,
                nickname,
                null,
                null
        ));
    }

    private String bearer(UserJpaEntity user) {
        return "Bearer " + tokenService
                .createAccessToken(user.getId())
                .value();
    }

    private void createPet(
            String bearer,
            String idempotencyKey,
            String name
    ) throws Exception {
        mockMvc.perform(post("/v1/pets")
                        .header("Authorization", bearer)
                        .header("X-Idempotency-Key", idempotencyKey)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "%s",
                                  "profileImage": null
                                }
                                """.formatted(name)))
                .andExpect(status().isCreated());
    }

    private void insertRobotState(Long petId, Long robotId) {
        jdbcTemplate.update(
                """
                INSERT INTO robots (
                    id,
                    serial_number,
                    model_name,
                    updated_at
                )
                VALUES (?, ?, ?, CURRENT_TIMESTAMP)
                """,
                robotId,
                "PETBOT-" + robotId,
                "MYSIL-01"
        );
        jdbcTemplate.update(
                """
                INSERT INTO robot_pairings (
                    pet_id,
                    robot_id,
                    paired_at
                )
                VALUES (?, ?, CURRENT_TIMESTAMP)
                """,
                petId,
                robotId
        );
        jdbcTemplate.update(
                """
                INSERT INTO robot_current_states (
                    robot_id,
                    online,
                    mode,
                    battery_level,
                    docked,
                    updated_at
                )
                VALUES (?, TRUE, 'IDLE', 82, FALSE, CURRENT_TIMESTAMP)
                """,
                robotId
        );
    }
}
