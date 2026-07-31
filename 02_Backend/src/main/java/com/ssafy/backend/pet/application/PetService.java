package com.ssafy.backend.pet.application;

import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import com.ssafy.backend.pet.infrastructure.persistence.PetCreationRequestJpaEntity;
import com.ssafy.backend.pet.infrastructure.persistence.PetJpaEntity;
import com.ssafy.backend.pet.infrastructure.persistence.PetRobotStatusProjection;
import com.ssafy.backend.pet.infrastructure.persistence.SpringDataPetAffinityStateRepository;
import com.ssafy.backend.pet.infrastructure.persistence.SpringDataPetCreationRequestRepository;
import com.ssafy.backend.pet.infrastructure.persistence.SpringDataPetRepository;
import com.ssafy.backend.user.infrastructure.persistence.SpringDataUserRepository;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;

@Service
public class PetService {

    private final SpringDataPetRepository petRepository;
    private final SpringDataPetAffinityStateRepository affinityRepository;
    private final SpringDataPetCreationRequestRepository creationRequestRepository;
    private final SpringDataUserRepository userRepository;
    private final PetCreationTransactionService creationTransactionService;

    public PetService(
            SpringDataPetRepository petRepository,
            SpringDataPetAffinityStateRepository affinityRepository,
            SpringDataPetCreationRequestRepository creationRequestRepository,
            SpringDataUserRepository userRepository,
            PetCreationTransactionService creationTransactionService
    ) {
        this.petRepository = petRepository;
        this.affinityRepository = affinityRepository;
        this.creationRequestRepository = creationRequestRepository;
        this.userRepository = userRepository;
        this.creationTransactionService = creationTransactionService;
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
        return toProfileResult(findOwnedPet(petId, userId));
    }

    @Transactional
    public PetProfileResult update(
            Long userId,
            Long petId,
            String name
    ) {
        PetJpaEntity pet = petRepository
                .findOwnedByIdForUpdate(petId, userId)
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.PET_NOT_FOUND
                ));
        pet.changeName(normalizeName(name));
        petRepository.flush();
        return toProfileResult(pet);
    }

    private PetJpaEntity findOwnedPet(Long petId, Long userId) {
        return petRepository
                .findByIdAndUserIdAndDeletedAtIsNull(petId, userId)
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
                findAffinity(pet.getId()),
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
                findAffinity(pet.getId()),
                robot
        );
    }

    private PetAffinityResult findAffinity(Long petId) {
        return affinityRepository.findById(petId)
                .map(state -> new PetAffinityResult(
                        state.getAffinityScore(),
                        state.getAffinityLevel(),
                        state.getMood()
                ))
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.PET_AFFINITY_STATE_NOT_FOUND
                ));
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
