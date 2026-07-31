package com.ssafy.backend.robot.application;

import com.ssafy.backend.auth.service.TokenHashService;
import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import com.ssafy.backend.robot.infrastructure.persistence.PetReferenceJpaEntity;
import com.ssafy.backend.robot.infrastructure.persistence.RobotCredentialJpaEntity;
import com.ssafy.backend.robot.infrastructure.persistence.RobotJpaEntity;
import com.ssafy.backend.robot.infrastructure.persistence.RobotPairingJpaEntity;
import com.ssafy.backend.robot.infrastructure.persistence.SpringDataPetReferenceRepository;
import com.ssafy.backend.robot.infrastructure.persistence.SpringDataRobotCredentialRepository;
import com.ssafy.backend.robot.infrastructure.persistence.SpringDataRobotPairingRepository;
import com.ssafy.backend.robot.infrastructure.persistence.SpringDataRobotRepository;
import org.hibernate.exception.ConstraintViolationException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class RobotPairingServiceTest {

    private static final Instant NOW = Instant.parse("2026-07-29T03:15:00Z");
    private static final Long USER_ID = 1L;
    private static final Long PET_ID = 201L;
    private static final Long ROBOT_ID = 301L;

    private SpringDataPetReferenceRepository petRepository;
    private SpringDataRobotRepository robotRepository;
    private SpringDataRobotCredentialRepository credentialRepository;
    private SpringDataRobotPairingRepository pairingRepository;
    private TokenHashService tokenHashService;
    private RobotPairingService service;

    @BeforeEach
    void setUp() {
        petRepository = mock(SpringDataPetReferenceRepository.class);
        robotRepository = mock(SpringDataRobotRepository.class);
        credentialRepository = mock(SpringDataRobotCredentialRepository.class);
        pairingRepository = mock(SpringDataRobotPairingRepository.class);
        tokenHashService = mock(TokenHashService.class);
        service = new RobotPairingService(
                petRepository,
                robotRepository,
                credentialRepository,
                pairingRepository,
                tokenHashService,
                Clock.fixed(NOW, ZoneOffset.UTC)
        );
    }

    @Test
    void pairsRobotUsingStaticQrToken() {
        PetReferenceJpaEntity pet = mock(PetReferenceJpaEntity.class);
        RobotCredentialJpaEntity credential = mock(RobotCredentialJpaEntity.class);
        RobotJpaEntity robot = mock(RobotJpaEntity.class);
        RobotPairingJpaEntity pairing = mock(RobotPairingJpaEntity.class);
        when(pet.getId()).thenReturn(PET_ID);
        when(credential.getRobotId()).thenReturn(ROBOT_ID);
        when(robot.getId()).thenReturn(ROBOT_ID);
        when(robot.getSerialNumber()).thenReturn("PETBOT-A203-0001");
        when(robot.getModelName()).thenReturn("MYSIL-01");
        when(robot.getFirmwareVersion()).thenReturn("1.0.0");
        when(pairing.getId()).thenReturn(401L);
        when(pairing.getPairedAt()).thenReturn(NOW);
        when(petRepository.findByIdAndUserIdAndDeletedAtIsNull(PET_ID, USER_ID))
                .thenReturn(Optional.of(pet));
        when(tokenHashService.hash("static-qr-token")).thenReturn("qr-token-hash");
        when(credentialRepository.findByQrTokenHash("qr-token-hash"))
                .thenReturn(Optional.of(credential));
        when(robotRepository.findByIdForUpdate(ROBOT_ID)).thenReturn(Optional.of(robot));
        when(pairingRepository.saveAndFlush(any(RobotPairingJpaEntity.class)))
                .thenReturn(pairing);

        RobotPairingResult result = service.pair(USER_ID, PET_ID, "static-qr-token");

        assertEquals(401L, result.pairingId());
        assertEquals(ROBOT_ID, result.robotId());
        assertEquals(PET_ID, result.petId());
        assertEquals("PETBOT-A203-0001", result.serialNumber());
        verify(robot).claimOwnershipIfUnowned(USER_ID, NOW);
        verify(credential).markQrTokenUsed(NOW);
    }

    @Test
    void rejectsPetNotOwnedByAuthenticatedUser() {
        when(petRepository.findByIdAndUserIdAndDeletedAtIsNull(PET_ID, USER_ID))
                .thenReturn(Optional.empty());

        BusinessException exception = assertThrows(
                BusinessException.class,
                () -> service.pair(USER_ID, PET_ID, "static-qr-token")
        );

        assertEquals(ErrorCode.PET_NOT_FOUND, exception.errorCode());
        verify(credentialRepository, never()).findByQrTokenHash(any());
    }

    @Test
    void rejectsInvalidQrToken() {
        PetReferenceJpaEntity pet = mock(PetReferenceJpaEntity.class);
        when(petRepository.findByIdAndUserIdAndDeletedAtIsNull(PET_ID, USER_ID))
                .thenReturn(Optional.of(pet));
        when(tokenHashService.hash("invalid-token")).thenReturn("invalid-hash");
        when(credentialRepository.findByQrTokenHash("invalid-hash"))
                .thenReturn(Optional.empty());

        BusinessException exception = assertThrows(
                BusinessException.class,
                () -> service.pair(USER_ID, PET_ID, "invalid-token")
        );

        assertEquals(ErrorCode.INVALID_QR_TOKEN, exception.errorCode());
    }

    @Test
    void rejectsExpiredQrToken() {
        PetReferenceJpaEntity pet = mock(PetReferenceJpaEntity.class);
        RobotCredentialJpaEntity credential = mock(RobotCredentialJpaEntity.class);
        RobotJpaEntity robot = mock(RobotJpaEntity.class);
        when(petRepository.findByIdAndUserIdAndDeletedAtIsNull(PET_ID, USER_ID))
                .thenReturn(Optional.of(pet));
        when(tokenHashService.hash("expired-token")).thenReturn("expired-hash");
        when(credentialRepository.findByQrTokenHash("expired-hash"))
                .thenReturn(Optional.of(credential));
        when(credential.getRobotId()).thenReturn(ROBOT_ID);
        when(robotRepository.findByIdForUpdate(ROBOT_ID)).thenReturn(Optional.of(robot));
        when(credential.isQrTokenExpiredAt(NOW)).thenReturn(true);

        BusinessException exception = assertThrows(
                BusinessException.class,
                () -> service.pair(USER_ID, PET_ID, "expired-token")
        );

        assertEquals(ErrorCode.QR_TOKEN_EXPIRED, exception.errorCode());
    }

    @Test
    void rejectsRobotWithActivePairing() {
        PetReferenceJpaEntity pet = mock(PetReferenceJpaEntity.class);
        RobotCredentialJpaEntity credential = mock(RobotCredentialJpaEntity.class);
        RobotJpaEntity robot = mock(RobotJpaEntity.class);
        when(pet.getId()).thenReturn(PET_ID);
        when(credential.getRobotId()).thenReturn(ROBOT_ID);
        when(robot.getId()).thenReturn(ROBOT_ID);
        when(petRepository.findByIdAndUserIdAndDeletedAtIsNull(PET_ID, USER_ID))
                .thenReturn(Optional.of(pet));
        when(tokenHashService.hash("static-qr-token")).thenReturn("qr-token-hash");
        when(credentialRepository.findByQrTokenHash("qr-token-hash"))
                .thenReturn(Optional.of(credential));
        when(robotRepository.findByIdForUpdate(ROBOT_ID)).thenReturn(Optional.of(robot));
        when(pairingRepository.existsByRobotIdAndUnpairedAtIsNull(ROBOT_ID))
                .thenReturn(true);

        BusinessException exception = assertThrows(
                BusinessException.class,
                () -> service.pair(USER_ID, PET_ID, "static-qr-token")
        );

        assertEquals(ErrorCode.ROBOT_ALREADY_PAIRED, exception.errorCode());
    }

    @Test
    void returnsExistingPairingForIdempotentRetry() {
        PetReferenceJpaEntity pet = mock(PetReferenceJpaEntity.class);
        RobotCredentialJpaEntity credential = mock(RobotCredentialJpaEntity.class);
        RobotJpaEntity robot = mock(RobotJpaEntity.class);
        RobotPairingJpaEntity pairing = mock(RobotPairingJpaEntity.class);
        when(pet.getId()).thenReturn(PET_ID);
        when(credential.getRobotId()).thenReturn(ROBOT_ID);
        when(robot.getId()).thenReturn(ROBOT_ID);
        when(pairing.getId()).thenReturn(401L);
        when(pairing.getPairedAt()).thenReturn(NOW);
        when(petRepository.findByIdAndUserIdAndDeletedAtIsNull(PET_ID, USER_ID))
                .thenReturn(Optional.of(pet));
        when(tokenHashService.hash("static-qr-token")).thenReturn("qr-token-hash");
        when(credentialRepository.findByQrTokenHash("qr-token-hash"))
                .thenReturn(Optional.of(credential));
        when(robotRepository.findByIdForUpdate(ROBOT_ID)).thenReturn(Optional.of(robot));
        when(pairingRepository.findByPetIdAndRobotIdAndUnpairedAtIsNull(
                PET_ID,
                ROBOT_ID
        )).thenReturn(Optional.of(pairing));

        RobotPairingResult result = service.pair(USER_ID, PET_ID, "static-qr-token");

        assertEquals(401L, result.pairingId());
        verify(pairingRepository, never()).saveAndFlush(any());
        verify(robot).claimOwnershipIfUnowned(USER_ID, NOW);
        verify(credential).markQrTokenUsed(NOW);
    }

    @Test
    void rejectsRobotOwnedByAnotherUser() {
        PetReferenceJpaEntity pet = mock(PetReferenceJpaEntity.class);
        RobotCredentialJpaEntity credential = mock(RobotCredentialJpaEntity.class);
        RobotJpaEntity robot = mock(RobotJpaEntity.class);
        when(credential.getRobotId()).thenReturn(ROBOT_ID);
        when(petRepository.findByIdAndUserIdAndDeletedAtIsNull(PET_ID, USER_ID))
                .thenReturn(Optional.of(pet));
        when(tokenHashService.hash("static-qr-token")).thenReturn("qr-token-hash");
        when(credentialRepository.findByQrTokenHash("qr-token-hash"))
                .thenReturn(Optional.of(credential));
        when(robotRepository.findByIdForUpdate(ROBOT_ID)).thenReturn(Optional.of(robot));
        when(robot.isOwnedByAnotherUser(USER_ID)).thenReturn(true);

        BusinessException exception = assertThrows(
                BusinessException.class,
                () -> service.pair(USER_ID, PET_ID, "static-qr-token")
        );

        assertEquals(ErrorCode.ROBOT_OWNERSHIP_MISMATCH, exception.errorCode());
        verify(pairingRepository, never()).saveAndFlush(any());
    }

    @Test
    void rejectsPetWithAnotherActiveRobot() {
        PetReferenceJpaEntity pet = mock(PetReferenceJpaEntity.class);
        RobotCredentialJpaEntity credential = mock(RobotCredentialJpaEntity.class);
        RobotJpaEntity robot = mock(RobotJpaEntity.class);
        when(pet.getId()).thenReturn(PET_ID);
        when(credential.getRobotId()).thenReturn(ROBOT_ID);
        when(robot.getId()).thenReturn(ROBOT_ID);
        when(petRepository.findByIdAndUserIdAndDeletedAtIsNull(PET_ID, USER_ID))
                .thenReturn(Optional.of(pet));
        when(tokenHashService.hash("static-qr-token")).thenReturn("qr-token-hash");
        when(credentialRepository.findByQrTokenHash("qr-token-hash"))
                .thenReturn(Optional.of(credential));
        when(robotRepository.findByIdForUpdate(ROBOT_ID)).thenReturn(Optional.of(robot));
        when(pairingRepository.existsByPetIdAndUnpairedAtIsNull(PET_ID))
                .thenReturn(true);

        BusinessException exception = assertThrows(
                BusinessException.class,
                () -> service.pair(USER_ID, PET_ID, "static-qr-token")
        );

        assertEquals(ErrorCode.PET_ALREADY_PAIRED, exception.errorCode());
    }

    @Test
    void translatesDatabaseRobotConstraintToBusinessError() {
        PetReferenceJpaEntity pet = mock(PetReferenceJpaEntity.class);
        RobotCredentialJpaEntity credential = mock(RobotCredentialJpaEntity.class);
        RobotJpaEntity robot = mock(RobotJpaEntity.class);
        ConstraintViolationException constraint = mock(
                ConstraintViolationException.class
        );
        when(pet.getId()).thenReturn(PET_ID);
        when(credential.getRobotId()).thenReturn(ROBOT_ID);
        when(robot.getId()).thenReturn(ROBOT_ID);
        when(petRepository.findByIdAndUserIdAndDeletedAtIsNull(PET_ID, USER_ID))
                .thenReturn(Optional.of(pet));
        when(tokenHashService.hash("static-qr-token")).thenReturn("qr-token-hash");
        when(credentialRepository.findByQrTokenHash("qr-token-hash"))
                .thenReturn(Optional.of(credential));
        when(robotRepository.findByIdForUpdate(ROBOT_ID)).thenReturn(Optional.of(robot));
        when(constraint.getConstraintName())
                .thenReturn("uq_robot_pairings_active_robot");
        when(pairingRepository.saveAndFlush(any(RobotPairingJpaEntity.class)))
                .thenThrow(new DataIntegrityViolationException(
                        "duplicate pairing",
                        constraint
                ));

        BusinessException exception = assertThrows(
                BusinessException.class,
                () -> service.pair(USER_ID, PET_ID, "static-qr-token")
        );

        assertEquals(ErrorCode.ROBOT_ALREADY_PAIRED, exception.errorCode());
    }
}
