package com.ssafy.backend.user.service;

import com.ssafy.backend.auth.infrastructure.persistence.SpringDataAuthSessionRepository;
import com.ssafy.backend.auth.infrastructure.persistence.SpringDataSocialAccountRepository;
import com.ssafy.backend.auth.service.VerificationService;
import com.ssafy.backend.common.ApiException;
import com.ssafy.backend.user.dto.UpdateMemberRequest;
import com.ssafy.backend.user.infrastructure.persistence.SpringDataUserRepository;
import com.ssafy.backend.user.infrastructure.persistence.UserJpaEntity;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.Clock;
import java.time.Instant;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class MemberServiceTest {

    private SpringDataUserRepository userRepository;
    private MemberService memberService;

    @BeforeEach
    void setUp() {
        userRepository = mock(SpringDataUserRepository.class);
        memberService = new MemberService(
                userRepository,
                mock(SpringDataSocialAccountRepository.class),
                mock(SpringDataAuthSessionRepository.class),
                mock(VerificationService.class),
                mock(PasswordEncoder.class),
                Clock.systemUTC()
        );
    }

    @Test
    void translatesNicknameConstraintWithoutQueryingFailedTransaction() {
        UserJpaEntity user = new UserJpaEntity(
                "member@example.com",
                "password-hash",
                "기존닉네임",
                "01012345678",
                Instant.now()
        );
        ReflectionTestUtils.setField(user, "id", 1L);
        when(userRepository.findById(1L))
                .thenReturn(Optional.of(user));
        when(userRepository.existsByNicknameAndDeletedAtIsNullAndIdNot(
                "중복닉네임",
                1L
        )).thenReturn(false);
        doThrow(new DataIntegrityViolationException(
                "constraint [uq_users_nickname]"
        )).when(userRepository).flush();

        ApiException exception = assertThrows(
                ApiException.class,
                () -> memberService.updateMember(
                        1L,
                        new UpdateMemberRequest("중복닉네임", null, null)
                )
        );

        assertEquals("NICKNAME_ALREADY_IN_USE", exception.getCode());
        verify(userRepository, times(1))
                .existsByNicknameAndDeletedAtIsNullAndIdNot(
                        "중복닉네임",
                        1L
                );
    }

    @Test
    void translatesOptimisticLockConflict() {
        UserJpaEntity user = new UserJpaEntity(
                "member@example.com",
                "password-hash",
                "기존닉네임",
                "01012345678",
                Instant.now()
        );
        ReflectionTestUtils.setField(user, "id", 1L);
        when(userRepository.findById(1L))
                .thenReturn(Optional.of(user));
        when(userRepository.existsByNicknameAndDeletedAtIsNullAndIdNot(
                "새닉네임",
                1L
        )).thenReturn(false);
        doThrow(new ObjectOptimisticLockingFailureException(
                UserJpaEntity.class,
                1L
        )).when(userRepository).flush();

        ApiException exception = assertThrows(
                ApiException.class,
                () -> memberService.updateMember(
                        1L,
                        new UpdateMemberRequest("새닉네임", null, null)
                )
        );

        assertEquals("MEMBER_UPDATE_CONFLICT", exception.getCode());
    }
}
