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

        pairingRepository.findActiveByPetIdForUpdate(petId)
                .ifPresent(pairing -> unpairAndReleaseRobot(userId, pairing, now));
        pet.softDelete(now);
    }

    private void unpairAndReleaseRobot(
            Long userId,
            RobotPairingJpaEntity pairing,
            Instant now
    ) {
        RobotJpaEntity robot = robotRepository
                .findByIdForUpdate(pairing.getRobotId())
                .orElseThrow(() -> new BusinessException(ErrorCode.INVALID_REQUEST));
        pairing.unpair(now);
        robot.releaseOwnership(userId, now);
    }
}
