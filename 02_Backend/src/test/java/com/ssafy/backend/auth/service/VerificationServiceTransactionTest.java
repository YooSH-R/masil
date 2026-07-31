package com.ssafy.backend.auth.service;

import com.ssafy.backend.auth.domain.AuthVerification;
import com.ssafy.backend.auth.domain.VerificationPurpose;
import com.ssafy.backend.auth.dto.VerificationSendRequest;
import com.ssafy.backend.auth.dto.VerificationSendResponse;
import com.ssafy.backend.auth.repository.AuthVerificationRepository;
import com.ssafy.backend.auth.sms.SmsSender;
import com.ssafy.backend.common.ApiException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.AbstractPlatformTransactionManager;
import org.springframework.transaction.support.DefaultTransactionStatus;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class VerificationServiceTransactionTest {

    private AuthVerificationRepository repository;
    private SmsSender smsSender;
    private VerificationService service;

    @BeforeEach
    void setUp() {
        repository = mock(AuthVerificationRepository.class);
        smsSender = mock(SmsSender.class);
        service = new VerificationService(
                repository,
                smsSender,
                new BCryptPasswordEncoder(),
                new TokenHashService(),
                new TransactionTemplate(new TestTransactionManager()),
                180,
                600
        );
    }

    @Test
    void sendsSmsAfterDatabaseTransactionCommits() {
        when(repository.existsByPhoneNumberAndCreatedAtAfter(anyString(), any()))
                .thenAnswer(invocation -> {
                    assertTrue(TransactionSynchronizationManager
                            .isActualTransactionActive());
                    return false;
                });
        when(repository.save(any(AuthVerification.class)))
                .thenAnswer(invocation -> {
                    assertTrue(TransactionSynchronizationManager
                            .isActualTransactionActive());
                    return invocation.getArgument(0);
                });
        doAnswer(invocation -> {
            assertFalse(TransactionSynchronizationManager
                    .isActualTransactionActive());
            return null;
        }).when(smsSender).sendVerificationCode(anyString(), anyString());

        VerificationSendResponse response = service.send(
                new VerificationSendRequest(
                        "01012345678",
                        VerificationPurpose.SIGNUP
                )
        );

        assertNotNull(response.verificationId());
        assertNotNull(response.expiresAt());
    }

    @Test
    void removesPendingVerificationWhenSmsDeliveryFails() {
        when(repository.existsByPhoneNumberAndCreatedAtAfter(anyString(), any()))
                .thenReturn(false);
        when(repository.save(any(AuthVerification.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        doThrow(new IllegalStateException("SMS provider unavailable"))
                .when(smsSender)
                .sendVerificationCode(anyString(), anyString());
        when(repository.deleteByVerificationId(any(UUID.class)))
                .thenAnswer(invocation -> {
                    assertTrue(TransactionSynchronizationManager
                            .isActualTransactionActive());
                    return 1L;
                });

        ApiException exception = assertThrows(
                ApiException.class,
                () -> service.send(new VerificationSendRequest(
                        "01012345678",
                        VerificationPurpose.SIGNUP
                ))
        );

        assertEquals("SMS_SEND_FAILED", exception.getCode());
        verify(repository).deleteByVerificationId(any(UUID.class));
    }

    private static class TestTransactionManager
            extends AbstractPlatformTransactionManager {

        @Override
        protected Object doGetTransaction() {
            return new Object();
        }

        @Override
        protected void doBegin(
                Object transaction,
                TransactionDefinition definition
        ) {
        }

        @Override
        protected void doCommit(DefaultTransactionStatus status) {
        }

        @Override
        protected void doRollback(DefaultTransactionStatus status) {
        }
    }
}
