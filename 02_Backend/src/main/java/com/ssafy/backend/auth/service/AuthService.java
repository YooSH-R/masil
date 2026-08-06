package com.ssafy.backend.auth.service;

import com.ssafy.backend.auth.application.port.out.AuthTokenIssuer;
import com.ssafy.backend.auth.application.result.IssuedTokens;
import com.ssafy.backend.auth.infrastructure.persistence.AuthSessionJpaEntity;
import com.ssafy.backend.auth.infrastructure.persistence.SpringDataAuthSessionRepository;
import com.ssafy.backend.auth.dto.AuthResponse;
import com.ssafy.backend.auth.dto.LoginRequest;
import com.ssafy.backend.auth.dto.LogoutRequest;
import com.ssafy.backend.auth.dto.RefreshRequest;
import com.ssafy.backend.auth.dto.SignupRequest;
import com.ssafy.backend.common.ApiException;
import com.ssafy.backend.user.application.port.out.UserRepository;
import com.ssafy.backend.user.domain.User;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;

@Service
public class AuthService {

    private final UserRepository userRepository;
    private final SpringDataAuthSessionRepository authSessionRepository;
    private final PasswordEncoder passwordEncoder;
    private final TokenService tokenService;
    private final TokenHashService tokenHashService;
    private final VerificationService verificationService;
    private final AuthTokenIssuer authTokenIssuer;

    public AuthService(
            UserRepository userRepository,
            SpringDataAuthSessionRepository authSessionRepository,
            PasswordEncoder passwordEncoder,
            TokenService tokenService,
            TokenHashService tokenHashService,
            VerificationService verificationService,
            AuthTokenIssuer authTokenIssuer
    ) {
        this.userRepository = userRepository;
        this.authSessionRepository = authSessionRepository;
        this.passwordEncoder = passwordEncoder;
        this.tokenService = tokenService;
        this.tokenHashService = tokenHashService;
        this.verificationService = verificationService;
        this.authTokenIssuer = authTokenIssuer;
    }

    @Transactional
    public AuthResponse signup(SignupRequest request) {
        if (userRepository.existsByEmail(request.email())) {
            throw new ApiException(
                    HttpStatus.CONFLICT,
                    "EMAIL_ALREADY_IN_USE",
                    "이미 사용 중인 이메일입니다."
            );
        }

        if (userRepository.existsByNickname(request.nickname())) {
            throw new ApiException(
                    HttpStatus.CONFLICT,
                    "NICKNAME_ALREADY_IN_USE",
                    "이미 사용 중인 닉네임입니다."
            );
        }

        if (userRepository.existsByPhoneNumber(request.phoneNumber())) {
            throw new ApiException(
                    HttpStatus.CONFLICT,
                    "PHONE_NUMBER_ALREADY_IN_USE",
                    "이미 사용 중인 휴대전화 번호입니다."
            );
        }

        String phoneNumber = verificationService.consumeSignupToken(
                request.verificationToken(),
                request.phoneNumber()
        );

        User user = userRepository.save(
                User.newLocalUser(
                        request.email(),
                        passwordEncoder.encode(request.password()),
                        request.nickname(),
                        phoneNumber
                )
        );

        return issueTokens(user, request.deviceId());
    }

    @Transactional
    public AuthResponse login(LoginRequest request) {
        User user = userRepository
                .findByEmail(request.email())
                .filter(found -> found.passwordHash() != null)
                .filter(found -> passwordEncoder.matches(
                        request.password(),
                        found.passwordHash()
                ))
                .orElseThrow(() -> new ApiException(
                        HttpStatus.UNAUTHORIZED,
                        "INVALID_CREDENTIALS",
                        "이메일 또는 비밀번호가 올바르지 않습니다."
                ));

        return issueTokens(user, request.deviceId());
    }

    @Transactional
    public AuthResponse refresh(RefreshRequest request) {
        String tokenHash = tokenHashService.hash(request.refreshToken());
        AuthSessionJpaEntity session = authSessionRepository
                .findByRefreshTokenHash(tokenHash)
                .filter(found -> found.isUsableAt(Instant.now()))
                .filter(found -> found.getDeviceId().equals(request.deviceId()))
                .orElseThrow(() -> new ApiException(
                        HttpStatus.UNAUTHORIZED,
                        "REFRESH_TOKEN_INVALID",
                        "Refresh Token이 유효하지 않습니다."
                ));

        TokenService.AccessToken accessToken =
                tokenService.createAccessToken(
                        session.getUserId(),
                        session.getDeviceId(),
                        session.getId()
                );
        TokenService.RefreshToken refreshToken =
                tokenService.createRefreshToken();

        session.rotate(
                tokenHashService.hash(refreshToken.value()),
                refreshToken.expiresAt()
        );

        return AuthResponse.of(
                accessToken.value(),
                refreshToken.value(),
                accessToken.expiresAt(),
                refreshToken.expiresAt(),
                userRepository.findById(session.getUserId())
                        .orElseThrow(() -> new ApiException(
                                HttpStatus.UNAUTHORIZED,
                                "REFRESH_TOKEN_INVALID",
                                "Refresh Token이 유효하지 않습니다."
                        ))
        );
    }

    @Transactional
    public void logout(Long userId, LogoutRequest request) {
        String tokenHash = tokenHashService.hash(request.refreshToken());
        AuthSessionJpaEntity session = authSessionRepository
                .findByRefreshTokenHash(tokenHash)
                .filter(found -> found.getUserId().equals(userId))
                .filter(found -> found.getDeviceId().equals(request.deviceId()))
                .orElseThrow(() -> new ApiException(
                        HttpStatus.UNAUTHORIZED,
                        "REFRESH_TOKEN_INVALID",
                        "Refresh Token이 유효하지 않습니다."
                ));

        session.revoke();
    }

    private AuthResponse issueTokens(User user, String deviceId) {
        IssuedTokens tokens = authTokenIssuer.issue(user, deviceId);

        return AuthResponse.of(
                tokens.accessToken(),
                tokens.refreshToken(),
                tokens.accessTokenExpiresAt(),
                tokens.refreshTokenExpiresAt(),
                user
        );
    }
}
