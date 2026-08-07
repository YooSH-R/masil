package com.ssafy.backend.pet.application;

import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import com.ssafy.backend.pet.infrastructure.persistence.PetAffinityStateJpaEntity;
import com.ssafy.backend.pet.infrastructure.persistence.PetCreationRequestJpaEntity;
import com.ssafy.backend.pet.infrastructure.persistence.PetJpaEntity;
import com.ssafy.backend.pet.infrastructure.persistence.PetRobotStatusProjection;
import com.ssafy.backend.pet.infrastructure.persistence.SpringDataPetCreationRequestRepository;
import com.ssafy.backend.pet.infrastructure.persistence.SpringDataPetRepository;
import com.ssafy.backend.user.infrastructure.persistence.SpringDataUserRepository;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.List;

@Service
public class PetService {

    private final SpringDataPetRepository petRepository;
    private final SpringDataPetCreationRequestRepository creationRequestRepository;
    private final SpringDataUserRepository userRepository;
    private final PetCreationTransactionService creationTransactionService;
    private final Long localTestPetId;

    public PetService(
            SpringDataPetRepository petRepository,
            SpringDataPetCreationRequestRepository creationRequestRepository,
            SpringDataUserRepository userRepository,
            PetCreationTransactionService creationTransactionService,
            @Value("${pet.local-test-pet-id:}") String localTestPetId
    ) {
        this.petRepository = petRepository;
        this.creationRequestRepository = creationRequestRepository;
        this.userRepository = userRepository;
        this.creationTransactionService = creationTransactionService;
        this.localTestPetId = localTestPetId.isBlank()
                ? null
                : Long.valueOf(localTestPetId);
    }

    public PetCreatedResult create(
            Long userId,
            String idempotencyKey,
            String name
    ) {
        userRepository.findByIdAndDeletedAtIsNull(userId)
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.INVALID_REQUEST
                ));

        String normalizedName = normalizeName(name);
        String requestHash = hashCreationRequest(normalizedName);
        PetCreationRequestJpaEntity previous = findCreationRequest(
                userId,
                idempotencyKey
        );
        if (previous != null) {
            return replayCreation(previous, userId, requestHash);
        }

        try {
            PetJpaEntity pet = creationTransactionService.create(
                    userId,
                    idempotencyKey,
                    requestHash,
                    normalizedName
            );
            return toCreatedResult(pet);
        } catch (DataIntegrityViolationException exception) {
            PetCreationRequestJpaEntity concurrentRequest =
                    findCreationRequest(userId, idempotencyKey);
            if (concurrentRequest == null) {
                throw exception;
            }
            return replayCreation(
                    concurrentRequest,
                    userId,
                    requestHash
            );
        }
    }

    @Transactional(readOnly = true)
    public PetProfileResult getProfile(Long userId, Long petId) {
        PetJpaEntity pet = petRepository
                .findOwnedWithAffinity(petId, userId)
                .orElseGet(this::findLocalTestPet);
        return toProfileResult(pet);
    }

    @Transactional(readOnly = true)
    public List<PetProfileResult> getProfiles(Long userId) {
        return petRepository.findAllOwnedWithAffinity(userId).stream()
                .map(this::toProfileResult)
                .toList();
    }

    @Transactional(readOnly = true)
    public PetAffinitySnapshot getAffinity(Long userId, Long petId) {
        PetJpaEntity pet = findOwnedPet(petId, userId);
        PetAffinityStateJpaEntity state = pet.getAffinityState();
        if (state == null) {
            throw new BusinessException(
                    ErrorCode.PET_AFFINITY_STATE_NOT_FOUND
            );
        }
        return new PetAffinitySnapshot(
                pet.getId(),
                state.getAffinityScore(),
                state.getAffinityLevel(),
                state.getMood(),
                state.getUpdatedAt()
        );
    }

    private PetJpaEntity findLocalTestPet() {
        if (localTestPetId == null) {
            throw new BusinessException(ErrorCode.PET_NOT_FOUND);
        }
        return petRepository.findById(localTestPetId)
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.PET_NOT_FOUND
                ));
    }

    @Transactional
    public PetProfileResult update(
            Long userId,
            Long petId,
            String name,
            Integer dailyWalkCount
    ) {
        PetJpaEntity pet = petRepository
                .findOwnedWithAffinity(petId, userId)
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.PET_NOT_FOUND
                ));
        pet.changeName(normalizeName(name));
        // 보내지 않은 항목은 기존 값을 유지한다(부분 수정).
        if (dailyWalkCount != null) {
            pet.changeDailyWalkCount(dailyWalkCount);
        }
        return toProfileResult(pet);
    }

    private PetJpaEntity findOwnedPet(Long petId, Long userId) {
        return petRepository
                .findOwnedWithAffinity(petId, userId)
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.PET_NOT_FOUND
                ));
    }

    private PetCreationRequestJpaEntity findCreationRequest(
            Long userId,
            String idempotencyKey
    ) {
        return creationRequestRepository
                .findByUserIdAndIdempotencyKey(userId, idempotencyKey)
                .orElse(null);
    }

    private PetCreatedResult replayCreation(
            PetCreationRequestJpaEntity creationRequest,
            Long userId,
            String requestHash
    ) {
        if (!creationRequest.getRequestHash().equals(requestHash)) {
            throw new BusinessException(ErrorCode.INVALID_REQUEST);
        }
        return toCreatedResult(findOwnedPet(
                creationRequest.getPetId(),
                userId
        ));
    }

    private PetCreatedResult toCreatedResult(PetJpaEntity pet) {
        return new PetCreatedResult(
                pet.getId(),
                pet.getName(),
                toAffinityResult(pet.getAffinityState()),
                pet.getCreatedAt()
        );
    }

    private PetProfileResult toProfileResult(PetJpaEntity pet) {
        PetRobotResult robot = petRepository
                .findActiveRobotStatus(pet.getId())
                .map(this::toRobotResult)
                .orElse(null);
        return new PetProfileResult(
                pet.getId(),
                pet.getName(),
                null,
                pet.getDailyWalkCount(),
                toAffinityResult(pet.getAffinityState()),
                robot
        );
    }

    private PetAffinityResult toAffinityResult(
            PetAffinityStateJpaEntity state
    ) {
        if (state == null) {
            throw new BusinessException(
                    ErrorCode.PET_AFFINITY_STATE_NOT_FOUND
            );
        }
        return new PetAffinityResult(
                state.getAffinityScore(),
                state.getAffinityLevel(),
                state.getMood()
        );
    }

    private PetRobotResult toRobotResult(PetRobotStatusProjection status) {
        return new PetRobotResult(
                status.getRobotId(),
                Boolean.TRUE.equals(status.getOnline()),
                status.getBatteryLevel() == null
                        ? 0
                        : status.getBatteryLevel()
        );
    }

    private String normalizeName(String name) {
        return name.trim();
    }

    private String hashCreationRequest(String normalizedName) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest(
                    ("pet-create-v1\n" + normalizedName)
                            .getBytes(StandardCharsets.UTF_8)
            ));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException(
                    "SHA-256을 사용할 수 없습니다.",
                    exception
            );
        }
    }
}
