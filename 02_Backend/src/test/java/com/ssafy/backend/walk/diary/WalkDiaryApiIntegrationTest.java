package com.ssafy.backend.walk.diary;

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
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.http.AbortableInputStream;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Response;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;
import software.amazon.awssdk.services.s3.presigner.model.PresignedGetObjectRequest;

import java.io.ByteArrayInputStream;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@AutoConfigureMockMvc
@SpringBootTest(properties = {
        "storage.s3.enabled=true",
        "storage.s3.bucket=test-bucket",
        "storage.s3.region=ap-northeast-2",
        "storage.s3.presign-duration-seconds=300",
        "storage.s3.max-file-size-bytes=10485760",
        "storage.s3.max-markdown-bytes=1024",
        "storage.s3.api-call-attempt-timeout-seconds=2",
        "storage.s3.api-call-timeout-seconds=5"
})
class WalkDiaryApiIntegrationTest {

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

    @MockitoBean
    private S3Client s3Client;

    @MockitoBean
    private S3Presigner presigner;

    private UserJpaEntity owner;
    private UserJpaEntity otherUser;

    @BeforeEach
    void setUp() throws Exception {
        resetData();
        owner = saveUser("owner@example.com", "산책주인");
        otherUser = saveUser("other@example.com", "다른주인");
        PetCreatedResult pet = petService.create(
                owner.getId(),
                "walk-diary-owner-pet",
                "몽이"
        );
        insertPairing(pet.petId());
        stubS3();
    }

    @Test
    void returnsOwnedDiaryFromFixedS3Path() throws Exception {
        mockMvc.perform(get(
                        "/v1/walk-diaries/{deviceId}/{walkDate}/{session}",
                        "device-001",
                        "2026-08-03",
                        1
                ).header("Authorization", bearer(owner)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.deviceId").value("device-001"))
                .andExpect(jsonPath("$.data.walkDate").value("2026-08-03"))
                .andExpect(jsonPath("$.data.session").value(1))
                .andExpect(jsonPath("$.data.imageUrl")
                        .value("https://example.com/story.png"))
                .andExpect(jsonPath("$.data.markdown").value("# 오늘의 산책"));
    }

    @Test
    void returnsDateGroupedFeedFromS3Sessions() throws Exception {
        mockMvc.perform(get("/v1/walk-diaries")
                        .queryParam("size", "1")
                        .header("Authorization", bearer(owner)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items[0].walkDate")
                        .value("2026-08-03"))
                .andExpect(jsonPath("$.data.items[0].walkCount").value(2))
                .andExpect(jsonPath("$.data.items[0].diaries[0].session")
                        .value(1))
                .andExpect(jsonPath("$.data.items[0].diaries[1].session")
                        .value(2))
                .andExpect(jsonPath("$.data.nextCursor")
                        .value("2026-08-03"))
                .andExpect(jsonPath("$.data.hasNext").value(true));

        mockMvc.perform(get("/v1/walk-diaries")
                        .queryParam("beforeDate", "2026-08-03")
                        .queryParam("size", "1")
                        .header("Authorization", bearer(owner)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items[0].walkDate")
                        .value("2026-08-02"));
    }

    @Test
    void hidesObjectsFromPreviousOwnerAfterRobotIsRepaired() throws Exception {
        PetCreatedResult previousPet = petService.create(
                otherUser.getId(),
                "walk-diary-previous-owner-pet",
                "보리"
        );
        jdbcTemplate.update("""
                INSERT INTO robot_pairings (
                    pet_id, robot_id, paired_at, unpaired_at
                ) VALUES (?, ?, ?, ?)
                """,
                previousPet.petId(),
                301L,
                java.sql.Timestamp.from(Instant.parse(
                        "2026-07-01T00:00:00Z"
                )),
                java.sql.Timestamp.from(Instant.parse(
                        "2026-07-31T00:00:00Z"
                ))
        );

        mockMvc.perform(get("/v1/walk-diaries")
                        .header("Authorization", bearer(owner)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items").isEmpty());
    }

    @Test
    void hidesDiaryFromUserWhoDoesNotOwnDevice() throws Exception {
        mockMvc.perform(get(
                        "/v1/walk-diaries/{deviceId}/{walkDate}/{session}",
                        "device-001",
                        "2026-08-03",
                        1
                ).header("Authorization", bearer(otherUser)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code")
                        .value("WALK_DIARY_NOT_FOUND"));
    }

    @Test
    void requiresAccessToken() throws Exception {
        mockMvc.perform(get(
                        "/v1/walk-diaries/{deviceId}/{walkDate}/{session}",
                        "device-001",
                        "2026-08-03",
                        1
                ))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void rejectsInvalidSession() throws Exception {
        mockMvc.perform(get(
                        "/v1/walk-diaries/{deviceId}/{walkDate}/{session}",
                        "device-001",
                        "2026-08-03",
                        7
                ).header("Authorization", bearer(owner)))
                .andExpect(status().isBadRequest());
    }

    @Test
    void rejectsInvalidFeedSize() throws Exception {
        mockMvc.perform(get("/v1/walk-diaries")
                        .queryParam("size", "0")
                        .header("Authorization", bearer(owner)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("INVALID_REQUEST"));
    }

    private void resetData() {
        jdbcTemplate.execute("DELETE FROM walk_locations");
        jdbcTemplate.execute("DELETE FROM walks");
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

    private UserJpaEntity saveUser(String email, String nickname) {
        return userRepository.saveAndFlush(new UserJpaEntity(
                email,
                null,
                nickname,
                null,
                null
        ));
    }

    private void insertPairing(long petId) {
        jdbcTemplate.update("""
                INSERT INTO robots (
                    id, serial_number, model_name, updated_at
                ) VALUES (?, ?, ?, CURRENT_TIMESTAMP)
                """,
                301L,
                "device-001",
                "MYSIL-01"
        );
        jdbcTemplate.update("""
                INSERT INTO robot_pairings (
                    pet_id, robot_id, paired_at
                ) VALUES (?, ?, CURRENT_TIMESTAMP)
                """,
                petId,
                301L
        );
    }

    private String bearer(UserJpaEntity user) {
        return "Bearer " + tokenService
                .createAccessToken(user.getId())
                .value();
    }

    private void stubS3() throws Exception {
        List<software.amazon.awssdk.services.s3.model.S3Object> objects =
                List.of(
                        object("2026-08-03", 2, "story_image.png"),
                        object("2026-08-03", 2, "walk_log.md"),
                        object("2026-08-03", 1, "story_image.png"),
                        object("2026-08-03", 1, "walk_log.md"),
                        object("2026-08-02", 1, "story_image.png"),
                        object("2026-08-02", 1, "walk_log.md")
                );
        when(s3Client.listObjectsV2(any(ListObjectsV2Request.class)))
                .thenReturn(ListObjectsV2Response.builder()
                        .contents(objects)
                        .isTruncated(false)
                        .build());

        byte[] markdown = "# 오늘의 산책".getBytes(StandardCharsets.UTF_8);
        when(s3Client.getObject(any(GetObjectRequest.class)))
                .thenAnswer(ignored -> new ResponseInputStream<>(
                        GetObjectResponse.builder()
                                .contentLength((long) markdown.length)
                                .build(),
                        AbortableInputStream.create(
                                new ByteArrayInputStream(markdown)
                        )
                ));
        PresignedGetObjectRequest signed =
                mock(PresignedGetObjectRequest.class);
        when(signed.url()).thenReturn(
                new URL("https://example.com/story.png")
        );
        when(presigner.presignGetObject(any(GetObjectPresignRequest.class)))
                .thenReturn(signed);
    }

    private software.amazon.awssdk.services.s3.model.S3Object object(
            String date,
            int session,
            String file
    ) {
        return software.amazon.awssdk.services.s3.model.S3Object.builder()
                .key("robot-images/device-001/" + date + "/session"
                        + session + "/" + file)
                .lastModified(Instant.parse("2026-08-03T05:00:00Z"))
                .build();
    }
}
