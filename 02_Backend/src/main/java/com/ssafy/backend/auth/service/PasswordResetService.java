package com.ssafy.backend.auth.service;

import com.ssafy.backend.auth.dto.PasswordResetRequest;
import com.ssafy.backend.auth.infrastructure.persistence.SpringDataAuthSessionRepository;
import com.ssafy.backend.common.ApiException;
import com.ssafy.backend.user.infrastructure.persistence.SpringDataUserRepository;
import com.ssafy.backend.user.infrastructure.persistence.UserJpaEntity;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Instant;

@Service
public class PasswordResetService {

    private final SpringDataUserRepository userRepository;
    private final SpringDataAuthSessionRepository authSessionRepository;
    private final VerificationService verificationService;
    private final PasswordEncoder passwordEncoder;
    private final Clock clock;

    public PasswordResetService(
            SpringDataUserRepository userRepository,
            SpringDataAuthSessionRepository authSessionRepository,
            VerificationService verificationService,
            PasswordEncoder passwordEncoder,
            Clock clock
    ) {
        this.userRepository = userRepository;
        this.authSessionRepository = authSessionRepository;
        this.verificationService = verificationService;
        this.passwordEncoder = passwordEncoder;
        this.clock = clock;
    }

    @Transactional
    public void reset(PasswordResetRequest request) {
        String phoneNumber = verificationService.consumePasswordResetToken(
                request.verificationToken(),
                request.phoneNumber()
        );
        UserJpaEntity user = userRepository
                .findActiveByPhoneNumberForUpdate(phoneNumber)
                .orElseThrow(() -> new ApiException(
                        HttpStatus.NOT_FOUND,
                        "MEMBER_NOT_FOUND",
                        "회원을 찾을 수 없습니다."
                ));
        if (user.getPasswordHash() == null) {
            throw new ApiException(
                    HttpStatus.CONFLICT,
                    "PASSWORD_NOT_CONFIGURED",
                    "비밀번호가 설정되지 않은 회원입니다."
            );
        }

        Instant now = clock.instant();
        user.changePasswordHash(
                passwordEncoder.encode(request.newPassword())
        );
        authSessionRepository.revokeAllByUserId(user.getId(), now);
    }
}
