package com.ssafy.backend.pet.application;

import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import com.ssafy.backend.pet.infrastructure.persistence.PetJpaEntity;
import com.ssafy.backend.pet.infrastructure.persistence.SpringDataPetRepository;
import com.ssafy.backend.robot.infrastructure.persistence.RobotJpaEntity;
import com.ssafy.backend.robot.infrastructure.persistence.RobotPairingJpaEntity;
import com.ssafy.backend.robot.infrastructure.persistence.SpringDataRobotPairingRepository;
import com.ssafy.backend.robot.infrastructure.persistence.SpringDataRobotRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class PetDeletionServiceTest {

    private static final Long USER_ID = 1L;
    private static final Long PET_ID = 2L;
    private static final Long ROBOT_ID = 3L;
    private static final Instant NOW = Instant.parse("2026-08-07T04:30:00Z");

    private SpringDataPetRepository petRepository;
    private SpringDataRobotPairingRepository pairingRepository;
    private SpringDataRobotRepository robotRepository;
    private PetDeletionService service;

    @BeforeEach
    void setUp() {
        petRepository = mock(SpringDataPetRepository.class);
        pairingRepository = mock(SpringDataRobotPairingRepository.class);
        robotRepository = mock(SpringDataRobotRepository.class);
        service = new PetDeletionService(
                petRepository,
                pairingRepository,
                robotRepository,
                Clock.fixed(NOW, ZoneOffset.UTC)
        );
    }

    @Test
    void unpairsRobotReleasesOwnershipAndSoftDeletesPet() {
        PetJpaEntity pet = mock(PetJpaEntity.class);
        RobotPairingJpaEntity pairing = mock(RobotPairingJpaEntity.class);
        RobotJpaEntity robot = mock(RobotJpaEntity.class);
        when(petRepository.findByIdAndUserIdAndDeletedAtIsNull(PET_ID, USER_ID))
                .thenReturn(Optional.of(pet));
        when(pairingRepository.findActiveByPetIdForUpdate(PET_ID))
                .thenReturn(Optional.of(pairing));
        when(pairing.getRobotId()).thenReturn(ROBOT_ID);
        when(robotRepository.findByIdForUpdate(ROBOT_ID)).thenReturn(Optional.of(robot));

        service.delete(USER_ID, PET_ID);

        verify(pairing).unpair(NOW);
        verify(robot).releaseOwnership(USER_ID, NOW);
        verify(pet).softDelete(NOW);
        verify(robotRepository, never()).delete(robot);
    }

    @Test
    void softDeletesPetEvenWhenNoActivePairingExists() {
        PetJpaEntity pet = mock(PetJpaEntity.class);
        when(petRepository.findByIdAndUserIdAndDeletedAtIsNull(PET_ID, USER_ID))
                .thenReturn(Optional.of(pet));
        when(pairingRepository.findActiveByPetIdForUpdate(PET_ID))
                .thenReturn(Optional.empty());

        service.delete(USER_ID, PET_ID);

        verify(pet).softDelete(NOW);
        verify(robotRepository, never()).findByIdForUpdate(ROBOT_ID);
    }

    @Test
    void rejectsDeletingAnotherUsersPet() {
        when(petRepository.findByIdAndUserIdAndDeletedAtIsNull(PET_ID, USER_ID))
                .thenReturn(Optional.empty());

        BusinessException exception = assertThrows(
                BusinessException.class,
                () -> service.delete(USER_ID, PET_ID)
        );

        assertEquals(ErrorCode.PET_NOT_FOUND, exception.errorCode());
    }
}
