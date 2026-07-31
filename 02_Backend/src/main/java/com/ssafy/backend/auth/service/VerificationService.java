package com.ssafy.backend.auth.service;

import com.ssafy.backend.auth.domain.AuthVerification;
import com.ssafy.backend.auth.domain.VerificationPurpose;
import com.ssafy.backend.auth.dto.VerificationConfirmRequest;
import com.ssafy.backend.auth.dto.VerificationConfirmResponse;
import com.ssafy.backend.auth.dto.VerificationSendRequest;
import com.ssafy.backend.auth.dto.VerificationSendResponse;
import com.ssafy.backend.auth.repository.AuthVerificationRepository;
import com.ssafy.backend.auth.sms.SmsSender;
import com.ssafy.backend.common.ApiException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.time.Instant;
import java.util.Base64;
import java.util.UUID;

@Service
public class VerificationService {

    private static final int MAX_ATTEMPTS = 5;
    private static final long SEND_COOLDOWN_SECONDS = 60;

    private final AuthVerificationRepository repository;
    private final SmsSender smsSender;
    private final PasswordEncoder passwordEncoder;
    private final TokenHashService tokenHashService;
    private final SecureRandom secureRandom = new SecureRandom();
    private final long codeValiditySeconds;
    private final long tokenValiditySeconds;

    public VerificationService(
            AuthVerificationRepository repository,
            SmsSender smsSender,
            PasswordEncoder passwordEncoder,
            TokenHashService tokenHashService,
            @Value("${auth.verification.code-validity-seconds:180}") long codeValiditySeconds,
            @Value("${auth.verification.token-validity-seconds:600}") long tokenValiditySeconds
    ) {
        this.repository = repository;
        this.smsSender = smsSender;
        this.passwordEncoder = passwordEncoder;
        this.tokenHashService = tokenHashService;
        this.codeValiditySeconds = codeValiditySeconds;
        this.tokenValiditySeconds = tokenValiditySeconds;
    }

    @Transactional
    public VerificationSendResponse send(VerificationSendRequest request) {
        String phoneNumber = normalizePhoneNumber(request.phoneNumber());
        if (repository.existsByPhoneNumberAndCreatedAtAfter(
                phoneNumber,
                Instant.now().minusSeconds(SEND_COOLDOWN_SECONDS)
        )) {
            throw new ApiException(
                    HttpStatus.TOO_MANY_REQUESTS,
                    "VERIFICATION_SEND_TOO_FREQUENT",
                    "인증번호는 60초 후 다시 요청할 수 있습니다."
            );
        }

        String code = String.format("%06d", secureRandom.nextInt(1_000_000));
        UUID verificationId = UUID.randomUUID();
        Instant expiresAt = Instant.now().plusSeconds(codeValiditySeconds);

        repository.save(AuthVerification.create(
                verificationId,
                phoneNumber,
                request.purpose() == null
                        ? VerificationPurpose.SIGNUP
                        : request.purpose(),
                passwordEncoder.encode(code),
                expiresAt
        ));

        try {
            smsSender.sendVerificationCode(phoneNumber, code);
        } catch (RuntimeException exception) {
            throw new ApiException(
                    HttpStatus.BAD_GATEWAY,
                    "SMS_SEND_FAILED",
                    "인증번호 발송에 실패했습니다."
            );
        }

        return new VerificationSendResponse(verificationId, expiresAt);
    }

    @Transactional(noRollbackFor = ApiException.class)
    public VerificationConfirmResponse confirm(
            UUID verificationId,
            VerificationConfirmRequest request
    ) {
        AuthVerification verification = repository.findByVerificationId(verificationId)
                .orElseThrow(() -> invalidCode("인증 요청을 찾을 수 없습니다."));
        Instant now = Instant.now();

        if (!verification.canConfirmAt(now, MAX_ATTEMPTS)) {
            throw invalidCode("인증번호가 만료되었거나 시도 횟수를 초과했습니다.");
        }
        if (!passwordEncoder.matches(request.code(), verification.getCodeHash())) {
            verification.recordFailure();
            throw invalidCode("인증번호가 올바르지 않습니다.");
        }

        String token = createToken();
        Instant tokenExpiresAt = now.plusSeconds(tokenValiditySeconds);
        verification.confirm(tokenHashService.hash(token), tokenExpiresAt, now);

        return new VerificationConfirmResponse(token, tokenExpiresAt);
    }

    @Transactional
    public String consumeSignupToken(String token, String phoneNumber) {
        return consumeToken(token, phoneNumber, VerificationPurpose.SIGNUP);
    }

    @Transactional
    public String consumePhoneVerificationToken(String token, String phoneNumber) {
        return consumeToken(token, phoneNumber, VerificationPurpose.SIGNUP);
    }

    @Transactional
    public String consumePasswordResetToken(String token, String phoneNumber) {
        return consumeToken(
                token,
                phoneNumber,
                VerificationPurpose.PASSWORD_RESET
        );
    }

    private String consumeToken(
            String token,
            String phoneNumber,
            VerificationPurpose expectedPurpose
    ) {
        String normalizedPhoneNumber = normalizePhoneNumber(phoneNumber);
        AuthVerification verification = repository
                .findByTokenHash(tokenHashService.hash(token))
                .orElseThrow(() -> new ApiException(
                        HttpStatus.UNAUTHORIZED,
                        "VERIFICATION_TOKEN_INVALID",
                        "휴대전화 인증이 필요합니다."
                ));

        if (!verification.getPhoneNumber().equals(normalizedPhoneNumber)
                || !verification.canUseTokenAt(Instant.now())) {
            throw new ApiException(
                    HttpStatus.UNAUTHORIZED,
                    "VERIFICATION_TOKEN_INVALID",
                    "휴대전화 인증이 필요합니다."
            );
        }
        if (verification.getPurpose() != expectedPurpose) {
            throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "VERIFICATION_PURPOSE_MISMATCH",
                    "인증 목적이 올바르지 않습니다."
            );
        }

        verification.markUsed(Instant.now());
        return normalizedPhoneNumber;
    }

    private String createToken() {
        byte[] bytes = new byte[32];
        secureRandom.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private String normalizePhoneNumber(String phoneNumber) {
        return phoneNumber.replaceAll("[^0-9]", "");
    }

    private ApiException invalidCode(String message) {
        return new ApiException(
                HttpStatus.BAD_REQUEST,
                "VERIFICATION_CODE_INVALID",
                message
        );
    }
}
