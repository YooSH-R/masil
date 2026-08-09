package com.ssafy.backend.pet.application;

import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import com.ssafy.backend.pet.infrastructure.persistence.PetJpaEntity;
import com.ssafy.backend.pet.infrastructure.persistence.SpringDataPetRepository;
import com.ssafy.backend.robot.infrastructure.persistence.RobotJpaEntity;
import com.ssafy.backend.robot.infrastructure.persistence.RobotPairingJpaEntity;
import com.ssafy.backend.robot.infrastructure.persistence.SpringDataRobotPairingRepository;
import com.ssafy.backend.robot.infrastructure.persistence.SpringDataRobotRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Instant;
import java.util.Objects;

@Service
public class PetDeletionService {

    private final SpringDataPetRepository petRepository;
    private final SpringDataRobotPairingRepository pairingRepository;
    private final SpringDataRobotRepository robotRepository;
    private final Clock clock;

    public PetDeletionService(
            SpringDataPetRepository petRepository,
            SpringDataRobotPairingRepository pairingRepository,
            SpringDataRobotRepository robotRepository,
            Clock clock
    ) {
        this.petRepository = petRepository;
        this.pairingRepository = pairingRepository;
        this.robotRepository = robotRepository;
        this.clock = clock;
    }

    /**
     * 활성 페어링과 기기 소유권을 해제한 뒤 펫만 소프트 삭제한다.
     * 기기·자격 증명·산책 기록·S3 객체는 삭제하지 않는다.
     */
    @Transactional
    public void delete(Long userId, Long petId) {
        PetJpaEntity pet = petRepository
                .findByIdAndUserIdAndDeletedAtIsNull(petId, userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.PET_NOT_FOUND));
        Instant now = clock.instant();

        pairingRepository.findByPetIdAndUnpairedAtIsNull(petId)
                .ifPresent(pairing -> unpairAndReleaseRobot(
                        userId,
                        petId,
                        pairing,
                        now
                ));
        pet.softDelete(now);
    }

    private void unpairAndReleaseRobot(
            Long userId,
            Long petId,
            RobotPairingJpaEntity pairingSnapshot,
            Instant now
    ) {
        RobotJpaEntity robot = robotRepository
                .findByIdForUpdate(pairingSnapshot.getRobotId())
                .orElseThrow(() -> new BusinessException(ErrorCode.INVALID_REQUEST));

        RobotPairingJpaEntity pairing = pairingRepository
                .findActiveByPetIdForUpdate(petId)
                .orElse(null);
        if (pairing == null) {
            return;
        }
        if (!Objects.equals(pairing.getPetId(), petId)
                || !Objects.equals(pairing.getRobotId(), robot.getId())) {
            throw new BusinessException(ErrorCode.ROBOT_PAIRING_STATE_CONFLICT);
        }

        pairing.unpair(now);
        robot.releaseOwnership(userId, now);
    }
}
