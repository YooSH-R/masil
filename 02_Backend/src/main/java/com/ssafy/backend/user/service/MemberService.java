package com.ssafy.backend.user.service;

import com.ssafy.backend.auth.infrastructure.persistence.SpringDataAuthSessionRepository;
import com.ssafy.backend.auth.infrastructure.persistence.SpringDataSocialAccountRepository;
import com.ssafy.backend.auth.service.VerificationService;
import com.ssafy.backend.common.ApiException;
import com.ssafy.backend.user.dto.ChangePasswordRequest;
import com.ssafy.backend.user.dto.MemberResponse;
import com.ssafy.backend.user.dto.UpdateMemberRequest;
import com.ssafy.backend.user.dto.WithdrawMemberRequest;
import com.ssafy.backend.user.infrastructure.persistence.SpringDataUserRepository;
import com.ssafy.backend.user.infrastructure.persistence.UserJpaEntity;
import org.hibernate.exception.ConstraintViolationException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

@Service
public class MemberService {

    private final SpringDataUserRepository userRepository;
    private final SpringDataSocialAccountRepository socialAccountRepository;
    private final SpringDataAuthSessionRepository authSessionRepository;
    private final VerificationService verificationService;
    private final PasswordEncoder passwordEncoder;
    private final Clock clock;

    public MemberService(
            SpringDataUserRepository userRepository,
            SpringDataSocialAccountRepository socialAccountRepository,
            SpringDataAuthSessionRepository authSessionRepository,
            VerificationService verificationService,
            PasswordEncoder passwordEncoder,
            Clock clock
    ) {
        this.userRepository = userRepository;
        this.socialAccountRepository = socialAccountRepository;
        this.authSessionRepository = authSessionRepository;
        this.verificationService = verificationService;
        this.passwordEncoder = passwordEncoder;
        this.clock = clock;
    }

    @Transactional(readOnly = true)
    public MemberResponse getMember(Long userId) {
        return toResponse(findActiveUser(userId));
    }

    @Transactional
    public MemberResponse updateMember(
            Long userId,
            UpdateMemberRequest request
    ) {
        if (request.nickname() == null && request.phoneNumber() == null) {
            throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "INVALID_REQUEST",
                    "변경할 회원정보를 입력해야 합니다."
            );
        }

        UserJpaEntity user = findActiveUser(userId);
        updateNickname(user, request.nickname());
        updatePhoneNumber(
                user,
                request.phoneNumber(),
                request.verificationToken()
        );

        try {
            userRepository.flush();
        } catch (ObjectOptimisticLockingFailureException exception) {
            throw memberUpdateConflict();
        } catch (DataIntegrityViolationException exception) {
            throw translateDuplicate(exception);
        }
        return toResponse(user);
    }

    @Transactional
    public void changePassword(
            Long userId,
            Long currentSessionId,
            ChangePasswordRequest request
    ) {
        UserJpaEntity user = findActiveUser(userId);
        if (user.getPasswordHash() == null) {
            throw new ApiException(
                    HttpStatus.CONFLICT,
                    "PASSWORD_NOT_CONFIGURED",
                    "비밀번호가 설정되지 않은 회원입니다."
            );
        }
        if (!passwordEncoder.matches(
                request.currentPassword(),
                user.getPasswordHash()
        )) {
            throw new ApiException(
                    HttpStatus.UNAUTHORIZED,
                    "CURRENT_PASSWORD_INVALID",
                    "현재 비밀번호가 올바르지 않습니다."
            );
        }
        if (currentSessionId == null) {
            throw currentSessionNotIdentified();
        }

        user.changePasswordHash(
                passwordEncoder.encode(request.newPassword())
        );
        flushUserChanges();
        authSessionRepository.revokeAllByUserIdExceptSessionId(
                userId,
                currentSessionId,
                clock.instant()
        );
    }

    @Transactional
    public void withdraw(Long userId, WithdrawMemberRequest request) {
        UserJpaEntity user = findActiveUser(userId);
        if (!"WITHDRAW".equals(request.confirmation())) {
            throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "INVALID_REQUEST",
                    "회원탈퇴 확인 문구가 올바르지 않습니다."
            );
        }
        if (user.getPasswordHash() != null
                && (request.currentPassword() == null
                || !passwordEncoder.matches(
                        request.currentPassword(),
                        user.getPasswordHash()
                ))) {
            throw new ApiException(
                    HttpStatus.UNAUTHORIZED,
                    "CURRENT_PASSWORD_INVALID",
                    "현재 비밀번호가 올바르지 않습니다."
            );
        }

        Instant now = clock.instant();
        user.withdraw(now);
        flushUserChanges();
        authSessionRepository.revokeAllByUserId(userId, now);
        socialAccountRepository.deleteByUserId(userId);
    }

    private void updateNickname(UserJpaEntity user, String nickname) {
        if (nickname == null || nickname.equals(user.getNickname())) {
            return;
        }
        user.changeNickname(nickname);
    }

    private void updatePhoneNumber(
            UserJpaEntity user,
            String phoneNumber,
            String verificationToken
    ) {
        if (phoneNumber == null || phoneNumber.equals(user.getPhoneNumber())) {
            return;
        }
        if (verificationToken == null || verificationToken.isBlank()) {
            throw new ApiException(
                    HttpStatus.UNAUTHORIZED,
                    "VERIFICATION_TOKEN_INVALID",
                    "휴대전화 번호 변경을 위한 인증이 필요합니다."
            );
        }
        if (userRepository.existsByPhoneNumberAndDeletedAtIsNullAndIdNot(
                phoneNumber,
                user.getId()
        )) {
            throw phoneNumberAlreadyInUse();
        }

        String verifiedPhoneNumber =
                verificationService.consumePhoneVerificationToken(
                        verificationToken,
                        phoneNumber
                );
        user.changePhoneNumber(verifiedPhoneNumber, clock.instant());
    }

    private UserJpaEntity findActiveUser(Long userId) {
        UserJpaEntity user = userRepository.findById(userId)
                .orElseThrow(this::memberNotFound);
        return requireActive(user);
    }

    private void flushUserChanges() {
        try {
            userRepository.flush();
        } catch (ObjectOptimisticLockingFailureException exception) {
            throw memberUpdateConflict();
        }
    }

    private UserJpaEntity requireActive(UserJpaEntity user) {
        if (user.getDeletedAt() != null) {
            throw new ApiException(
                    HttpStatus.CONFLICT,
                    "ALREADY_WITHDRAWN",
                    "이미 탈퇴한 회원입니다."
            );
        }
        return user;
    }

    private ApiException memberNotFound() {
        return new ApiException(
                HttpStatus.NOT_FOUND,
                "MEMBER_NOT_FOUND",
                "회원을 찾을 수 없습니다."
        );
    }

    private ApiException currentSessionNotIdentified() {
        return new ApiException(
                HttpStatus.UNAUTHORIZED,
                "CURRENT_SESSION_NOT_IDENTIFIED",
                "현재 로그인 세션을 확인할 수 없습니다. 다시 로그인해 주세요."
        );
    }

    private ApiException memberUpdateConflict() {
        return new ApiException(
                HttpStatus.CONFLICT,
                "MEMBER_UPDATE_CONFLICT",
                "회원정보가 동시에 변경되었습니다. 다시 시도해 주세요."
        );
    }

    private MemberResponse toResponse(UserJpaEntity user) {
        List<String> loginProviders = new ArrayList<>();
        if (user.getPasswordHash() != null) {
            loginProviders.add("LOCAL");
        }
        socialAccountRepository.findAllByUserIdOrderByIdAsc(user.getId())
                .stream()
                .map(account -> account.getProvider().name())
                .distinct()
                .forEach(loginProviders::add);

        return new MemberResponse(
                user.getId(),
                user.getEmail(),
                user.getNickname(),
                user.getPhoneNumber(),
                user.getPhoneVerifiedAt() != null,
                List.copyOf(loginProviders),
                user.getCreatedAt()
        );
    }

    private ApiException translateDuplicate(
            DataIntegrityViolationException exception
    ) {
        String constraintName = findConstraintName(exception);
        if (constraintName.contains("uq_users_phone_number")
                || constraintName.contains("users_phone_number_key")) {
            return phoneNumberAlreadyInUse();
        }
        return memberUpdateConflict();
    }

    private String findConstraintName(Throwable exception) {
        Throwable cause = exception;
        StringBuilder messages = new StringBuilder();
        while (cause != null) {
            if (cause instanceof ConstraintViolationException violation
                    && violation.getConstraintName() != null) {
                return violation.getConstraintName().toLowerCase(Locale.ROOT);
            }
            if (cause.getMessage() != null) {
                messages.append(' ').append(cause.getMessage());
            }
            cause = cause.getCause();
        }
        return messages.toString().toLowerCase(Locale.ROOT);
    }

    private ApiException phoneNumberAlreadyInUse() {
        return new ApiException(
                HttpStatus.CONFLICT,
                "PHONE_NUMBER_ALREADY_IN_USE",
                "이미 사용 중인 휴대전화 번호입니다."
        );
    }
}
