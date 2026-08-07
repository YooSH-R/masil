package com.ssafy.backend.robot.application;

import com.ssafy.backend.auth.service.TokenHashService;
import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import com.ssafy.backend.pet.infrastructure.persistence.PetJpaEntity;
import com.ssafy.backend.pet.infrastructure.persistence.SpringDataPetRepository;
import com.ssafy.backend.robot.infrastructure.persistence.RobotCredentialJpaEntity;
import com.ssafy.backend.robot.infrastructure.persistence.RobotJpaEntity;
import com.ssafy.backend.robot.infrastructure.persistence.RobotPairingJpaEntity;
import com.ssafy.backend.robot.infrastructure.persistence.SpringDataRobotCredentialRepository;
import com.ssafy.backend.robot.infrastructure.persistence.SpringDataRobotPairingRepository;
import com.ssafy.backend.robot.infrastructure.persistence.SpringDataRobotRepository;
import org.hibernate.exception.ConstraintViolationException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Instant;
import java.util.Optional;

@Service
public class RobotPairingService {

    private final SpringDataPetRepository petRepository;
    private final SpringDataRobotRepository robotRepository;
    private final SpringDataRobotCredentialRepository credentialRepository;
    private final SpringDataRobotPairingRepository pairingRepository;
    private final TokenHashService tokenHashService;
    private final Clock clock;

    public RobotPairingService(
            SpringDataPetRepository petRepository,
            SpringDataRobotRepository robotRepository,
            SpringDataRobotCredentialRepository credentialRepository,
            SpringDataRobotPairingRepository pairingRepository,
            TokenHashService tokenHashService,
            Clock clock
    ) {
        this.petRepository = petRepository;
        this.robotRepository = robotRepository;
        this.credentialRepository = credentialRepository;
        this.pairingRepository = pairingRepository;
        this.tokenHashService = tokenHashService;
        this.clock = clock;
    }

    @Transactional
    public RobotPairingResult pair(Long userId, Long petId, String qrToken) {
        PetJpaEntity pet = petRepository
                .findByIdAndUserIdAndDeletedAtIsNull(petId, userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.PET_NOT_FOUND));

        String qrTokenHash = tokenHashService.hash(qrToken);
        RobotCredentialJpaEntity credential = credentialRepository
                .findByQrTokenHash(qrTokenHash)
                .orElseThrow(() -> new BusinessException(ErrorCode.INVALID_QR_TOKEN));

        RobotJpaEntity robot = robotRepository
                .findByIdForUpdate(credential.getRobotId())
                .orElseThrow(() -> new BusinessException(ErrorCode.INVALID_QR_TOKEN));

        Instant now = clock.instant();
        if (robot.isOwnedByAnotherUser(userId)) {
            throw new BusinessException(ErrorCode.ROBOT_OWNERSHIP_MISMATCH);
        }

        Optional<RobotPairingJpaEntity> existingPairing = pairingRepository
                .findByPetIdAndRobotIdAndUnpairedAtIsNull(pet.getId(), robot.getId());
        if (existingPairing.isPresent()) {
            robot.claimOwnershipIfUnowned(userId, now);
            credential.markQrTokenUsed(now);
            return toResult(existingPairing.get(), robot, pet);
        }

        if (credential.isQrTokenExpiredAt(now)) {
            throw new BusinessException(ErrorCode.QR_TOKEN_EXPIRED);
        }
        if (pairingRepository.existsByPetIdAndUnpairedAtIsNull(pet.getId())) {
            throw new BusinessException(ErrorCode.PET_ALREADY_PAIRED);
        }
        if (pairingRepository.existsByRobotIdAndUnpairedAtIsNull(credential.getRobotId())) {
            throw new BusinessException(ErrorCode.ROBOT_ALREADY_PAIRED);
        }

        robot.claimOwnershipIfUnowned(userId, now);
        RobotPairingJpaEntity pairing;
        try {
            pairing = pairingRepository.saveAndFlush(
                    new RobotPairingJpaEntity(pet.getId(), robot.getId(), now)
            );
        } catch (DataIntegrityViolationException exception) {
            BusinessException pairingConflict = translatePairingConflict(exception);
            if (pairingConflict != null) {
                throw pairingConflict;
            }
            throw exception;
        }
        credential.markQrTokenUsed(now);

        return toResult(pairing, robot, pet);
    }

    @Transactional(readOnly = true)
    public RobotRegistrationPreview validateRegistration(Long userId, String qrToken) {
        RobotRegistrationContext context = loadRegistrationContext(userId, qrToken, false);
        return new RobotRegistrationPreview(
                context.robot().getSerialNumber(),
                context.robot().getModelName(),
                context.robot().getFirmwareVersion()
        );
    }

    /**
     * QR을 마지막으로 다시 검증한 뒤 새 펫 생성과 기기 연결을 한 트랜잭션으로
     * 처리한다. 어떤 단계에서든 실패하면 펫과 초기 친밀도 상태도 함께 롤백된다.
     */
    @Transactional
    public RobotPairingResult registerNewPet(
            Long userId,
            String petName,
            String qrToken
    ) {
        RobotRegistrationContext context = loadRegistrationContext(userId, qrToken, true);
        Instant now = clock.instant();

        PetJpaEntity pet = petRepository.saveAndFlush(
                new PetJpaEntity(userId, petName.trim())
        );
        context.robot().claimOwnershipIfUnowned(userId, now);

        RobotPairingJpaEntity pairing;
        try {
            pairing = pairingRepository.saveAndFlush(
                    new RobotPairingJpaEntity(pet.getId(), context.robot().getId(), now)
            );
        } catch (DataIntegrityViolationException exception) {
            BusinessException pairingConflict = translatePairingConflict(exception);
            if (pairingConflict != null) {
                throw pairingConflict;
            }
            throw exception;
        }

        context.credential().markQrTokenUsed(now);
        return toResult(pairing, context.robot(), pet);
    }

    private RobotRegistrationContext loadRegistrationContext(
            Long userId,
            String qrToken,
            boolean lockRobot
    ) {
        String qrTokenHash = tokenHashService.hash(qrToken);
        RobotCredentialJpaEntity credential = (lockRobot
                ? credentialRepository.findByQrTokenHash(qrTokenHash)
                : credentialRepository.findFirstByQrTokenHash(qrTokenHash))
                .orElseThrow(() -> new BusinessException(ErrorCode.INVALID_QR_TOKEN));

        RobotJpaEntity robot = (lockRobot
                ? robotRepository.findByIdForUpdate(credential.getRobotId())
                : robotRepository.findById(credential.getRobotId()))
                .orElseThrow(() -> new BusinessException(ErrorCode.INVALID_QR_TOKEN));

        Instant now = clock.instant();
        if (credential.isQrTokenExpiredAt(now)) {
            throw new BusinessException(ErrorCode.QR_TOKEN_EXPIRED);
        }
        if (robot.isOwnedByAnotherUser(userId)) {
            throw new BusinessException(ErrorCode.ROBOT_OWNERSHIP_MISMATCH);
        }
        if (pairingRepository.existsByRobotIdAndUnpairedAtIsNull(robot.getId())) {
            throw new BusinessException(ErrorCode.ROBOT_ALREADY_PAIRED);
        }
        return new RobotRegistrationContext(credential, robot);
    }

    private record RobotRegistrationContext(
            RobotCredentialJpaEntity credential,
            RobotJpaEntity robot
    ) {
    }

    private RobotPairingResult toResult(
            RobotPairingJpaEntity pairing,
            RobotJpaEntity robot,
            PetJpaEntity pet
    ) {
        return new RobotPairingResult(
                pairing.getId(),
                robot.getId(),
                pet.getId(),
                robot.getSerialNumber(),
                robot.getModelName(),
                robot.getFirmwareVersion(),
                pairing.getPairedAt()
        );
    }

    private BusinessException translatePairingConflict(
            DataIntegrityViolationException exception
    ) {
        Throwable cause = exception;
        while (cause != null) {
            if (cause instanceof ConstraintViolationException constraintViolation) {
                String constraintName = constraintViolation.getConstraintName();
                if (constraintName == null) {
                    return null;
                }
                return switch (constraintName) {
                    case "uq_robot_pairings_active_pet" ->
                            new BusinessException(ErrorCode.PET_ALREADY_PAIRED);
                    case "uq_robot_pairings_active_robot" ->
                            new BusinessException(ErrorCode.ROBOT_ALREADY_PAIRED);
                    default -> null;
                };
            }
            cause = cause.getCause();
        }
        return null;
    }
}
