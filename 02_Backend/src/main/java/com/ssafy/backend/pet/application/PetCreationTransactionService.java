package com.ssafy.backend.pet.application;

import com.ssafy.backend.pet.infrastructure.persistence.PetCreationRequestJpaEntity;
import com.ssafy.backend.pet.infrastructure.persistence.PetJpaEntity;
import com.ssafy.backend.pet.infrastructure.persistence.SpringDataPetCreationRequestRepository;
import com.ssafy.backend.pet.infrastructure.persistence.SpringDataPetRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class PetCreationTransactionService {

    private final SpringDataPetRepository petRepository;
    private final SpringDataPetCreationRequestRepository creationRequestRepository;

    public PetCreationTransactionService(
            SpringDataPetRepository petRepository,
            SpringDataPetCreationRequestRepository creationRequestRepository
    ) {
        this.petRepository = petRepository;
        this.creationRequestRepository = creationRequestRepository;
    }

    @Transactional
    public PetJpaEntity create(
            Long userId,
            String idempotencyKey,
            String requestHash,
            String name
    ) {
        PetJpaEntity pet = petRepository.save(
                new PetJpaEntity(userId, name)
        );
        creationRequestRepository.save(
                new PetCreationRequestJpaEntity(
                        userId,
                        idempotencyKey,
                        requestHash,
                        pet.getId()
                )
        );
        return pet;
    }
}
