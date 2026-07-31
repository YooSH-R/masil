package com.ssafy.backend.user;

import com.ssafy.backend.auth.domain.AuthVerification;
import com.ssafy.backend.auth.domain.SocialProvider;
import com.ssafy.backend.auth.domain.VerificationPurpose;
import com.ssafy.backend.auth.infrastructure.persistence.AuthSessionJpaEntity;
import com.ssafy.backend.auth.infrastructure.persistence.SocialAccountJpaEntity;
import com.ssafy.backend.auth.infrastructure.persistence.SpringDataAuthSessionRepository;
import com.ssafy.backend.auth.infrastructure.persistence.SpringDataSocialAccountRepository;
import com.ssafy.backend.auth.repository.AuthVerificationRepository;
import com.ssafy.backend.auth.service.TokenHashService;
import com.ssafy.backend.auth.service.TokenService;
import com.ssafy.backend.user.infrastructure.persistence.SpringDataUserRepository;
import com.ssafy.backend.user.infrastructure.persistence.UserJpaEntity;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.web.servlet.MockMvc;

import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@AutoConfigureMockMvc
@SpringBootTest
class MemberApiIntegrationTest {

    private static final String OLD_PASSWORD = "password1";
    private static final String NEW_PASSWORD = "newPassword2";
    private static final String CURRENT_DEVICE_ID = "current-device";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private SpringDataUserRepository userRepository;

    @Autowired
    private SpringDataSocialAccountRepository socialAccountRepository;

    @Autowired
    private SpringDataAuthSessionRepository authSessionRepository;

    @Autowired
    private AuthVerificationRepository verificationRepository;

    @Autowired
    private PasswordEncoder passwordEncoder;

    @Autowired
    private TokenService tokenService;

    @Autowired
    private TokenHashService tokenHashService;

    @BeforeEach
    void resetData() {
        authSessionRepository.deleteAll();
        socialAccountRepository.deleteAll();
        verificationRepository.deleteAll();
        userRepository.deleteAll();
    }

    @Test
    void getsMemberWithLocalAndSocialLoginProviders() throws Exception {
        UserJpaEntity user = saveLocalUser(
                "member@example.com",
                "마이실",
                "01012345678"
        );
        socialAccountRepository.save(new SocialAccountJpaEntity(
                user.getId(),
                SocialProvider.GOOGLE,
                "google-user-id",
                user.getEmail()
        ));

        mockMvc.perform(get("/v1/users/me")
                        .header("Authorization", bearer(user)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.memberId").value(user.getId()))
                .andExpect(jsonPath("$.data.email").value(user.getEmail()))
                .andExpect(jsonPath("$.data.nickname").value("마이실"))
                .andExpect(jsonPath("$.data.phoneNumber").value("01012345678"))
                .andExpect(jsonPath("$.data.phoneVerified").value(true))
                .andExpect(jsonPath("$.data.loginProviders[0]").value("LOCAL"))
                .andExpect(jsonPath("$.data.loginProviders[1]").value("GOOGLE"));
    }

    @Test
    void updatesOnlyProvidedNickname() throws Exception {
        UserJpaEntity user = saveLocalUser(
                "member@example.com",
                "기존닉네임",
                "01012345678"
        );

        mockMvc.perform(patch("/v1/users/me")
                        .header("Authorization", bearer(user))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "nickname": "새닉네임"
                                }
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.nickname").value("새닉네임"))
                .andExpect(jsonPath("$.data.phoneNumber").value("01012345678"));
    }

    @Test
    void updatesPhoneNumberWithSingleUseVerificationToken() throws Exception {
        UserJpaEntity user = saveLocalUser(
                "member@example.com",
                "마이실",
                "01012345678"
        );
        String verificationToken = confirmedToken(
                "01098765432",
                VerificationPurpose.SIGNUP
        );

        mockMvc.perform(patch("/v1/users/me")
                        .header("Authorization", bearer(user))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "phoneNumber": "01098765432",
                                  "verificationToken": "%s"
                                }
                                """.formatted(verificationToken)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.phoneNumber").value("01098765432"))
                .andExpect(jsonPath("$.data.phoneVerified").value(true));

        mockMvc.perform(patch("/v1/users/me")
                        .header("Authorization", bearer(user))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "phoneNumber": "01087654321",
                                  "verificationToken": "%s"
                                }
                                """.formatted(verificationToken)))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.error.code")
                        .value("VERIFICATION_TOKEN_INVALID"));
    }

    @Test
    void changesPasswordAndKeepsOnlyCurrentDeviceSession() throws Exception {
        UserJpaEntity user = saveLocalUser(
                "member@example.com",
                "마이실",
                "01012345678"
        );
        AuthSessionJpaEntity current = saveSession(
                user.getId(),
                CURRENT_DEVICE_ID,
                "current-refresh"
        );
        AuthSessionJpaEntity other = saveSession(
                user.getId(),
                "other-device",
                "other-refresh"
        );

        mockMvc.perform(patch("/v1/users/me/password")
                        .header("Authorization", bearer(user))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "currentPassword": "%s",
                                  "newPassword": "%s"
                                }
                                """.formatted(OLD_PASSWORD, NEW_PASSWORD)))
                .andExpect(status().isNoContent());

        UserJpaEntity changed = userRepository.findById(user.getId()).orElseThrow();
        assertTrue(passwordEncoder.matches(
                NEW_PASSWORD,
                changed.getPasswordHash()
        ));
        assertTrue(authSessionRepository.findById(current.getId())
                .orElseThrow()
                .isUsableAt(Instant.now()));
        assertFalse(authSessionRepository.findById(other.getId())
                .orElseThrow()
                .isUsableAt(Instant.now()));
    }

    @Test
    void rejectsPasswordChangeForSocialOnlyMember() throws Exception {
        UserJpaEntity user = userRepository.saveAndFlush(new UserJpaEntity(
                "social@example.com",
                null,
                "소셜회원",
                null,
                null
        ));

        mockMvc.perform(patch("/v1/users/me/password")
                        .header("Authorization", bearer(user))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "currentPassword": "password1",
                                  "newPassword": "newPassword2"
                                }
                                """))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error.code")
                        .value("PASSWORD_NOT_CONFIGURED"));
    }

    @Test
    void resetsPasswordWithPasswordResetTokenAndRevokesEverySession()
            throws Exception {
        UserJpaEntity user = saveLocalUser(
                "member@example.com",
                "마이실",
                "01012345678"
        );
        AuthSessionJpaEntity session = saveSession(
                user.getId(),
                CURRENT_DEVICE_ID,
                "refresh-token"
        );
        String verificationToken = confirmedToken(
                "01012345678",
                VerificationPurpose.PASSWORD_RESET
        );

        mockMvc.perform(post("/v1/auth/password/reset")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "phoneNumber": "01012345678",
                                  "verificationToken": "%s",
                                  "newPassword": "%s"
                                }
                                """.formatted(
                                verificationToken,
                                NEW_PASSWORD
                        )))
                .andExpect(status().isNoContent());

        UserJpaEntity changed = userRepository.findById(user.getId()).orElseThrow();
        assertTrue(passwordEncoder.matches(
                NEW_PASSWORD,
                changed.getPasswordHash()
        ));
        assertFalse(authSessionRepository.findById(session.getId())
                .orElseThrow()
                .isUsableAt(Instant.now()));
    }

    @Test
    void rejectsSignupTokenForPasswordReset() throws Exception {
        saveLocalUser("member@example.com", "마이실", "01012345678");
        String verificationToken = confirmedToken(
                "01012345678",
                VerificationPurpose.SIGNUP
        );

        mockMvc.perform(post("/v1/auth/password/reset")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "phoneNumber": "01012345678",
                                  "verificationToken": "%s",
                                  "newPassword": "%s"
                                }
                                """.formatted(
                                verificationToken,
                                NEW_PASSWORD
                        )))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code")
                        .value("VERIFICATION_PURPOSE_MISMATCH"));
    }

    @Test
    void withdrawsMemberAndRemovesPersonallyIdentifiableLoginData()
            throws Exception {
        UserJpaEntity user = saveLocalUser(
                "member@example.com",
                "마이실",
                "01012345678"
        );
        socialAccountRepository.save(new SocialAccountJpaEntity(
                user.getId(),
                SocialProvider.KAKAO,
                "kakao-user-id",
                user.getEmail()
        ));
        AuthSessionJpaEntity session = saveSession(
                user.getId(),
                CURRENT_DEVICE_ID,
                "refresh-token"
        );

        mockMvc.perform(delete("/v1/users/me")
                        .header("Authorization", bearer(user))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "currentPassword": "%s",
                                  "confirmation": "WITHDRAW"
                                }
                                """.formatted(OLD_PASSWORD)))
                .andExpect(status().isNoContent());

        UserJpaEntity withdrawn =
                userRepository.findById(user.getId()).orElseThrow();
        assertNull(withdrawn.getEmail());
        assertNull(withdrawn.getPasswordHash());
        assertNull(withdrawn.getPhoneNumber());
        assertTrue(withdrawn.getNickname().startsWith("withdrawn-"));
        assertTrue(withdrawn.getDeletedAt() != null);
        assertTrue(socialAccountRepository
                .findAllByUserIdOrderByIdAsc(user.getId())
                .isEmpty());
        assertFalse(authSessionRepository.findById(session.getId())
                .orElseThrow()
                .isUsableAt(Instant.now()));
    }

    private UserJpaEntity saveLocalUser(
            String email,
            String nickname,
            String phoneNumber
    ) {
        return userRepository.saveAndFlush(new UserJpaEntity(
                email,
                passwordEncoder.encode(OLD_PASSWORD),
                nickname,
                phoneNumber,
                Instant.now()
        ));
    }

    private AuthSessionJpaEntity saveSession(
            Long userId,
            String deviceId,
            String refreshToken
    ) {
        return authSessionRepository.saveAndFlush(new AuthSessionJpaEntity(
                userId,
                deviceId,
                tokenHashService.hash(refreshToken),
                Instant.now().plusSeconds(3600)
        ));
    }

    private String confirmedToken(
            String phoneNumber,
            VerificationPurpose purpose
    ) {
        String token = UUID.randomUUID().toString();
        Instant now = Instant.now();
        AuthVerification verification = AuthVerification.create(
                UUID.randomUUID(),
                phoneNumber,
                purpose,
                passwordEncoder.encode("123456"),
                now.plusSeconds(180)
        );
        verification.confirm(
                tokenHashService.hash(token),
                now.plusSeconds(600),
                now
        );
        verificationRepository.saveAndFlush(verification);
        return token;
    }

    private String bearer(UserJpaEntity user) {
        return "Bearer " + tokenService
                .createAccessToken(user.getId(), CURRENT_DEVICE_ID)
                .value();
    }
}
