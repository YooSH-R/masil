package com.ssafy.backend.user.infrastructure.persistence;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface SpringDataUserRepository extends JpaRepository<UserJpaEntity, Long> {

    boolean existsByEmailIgnoreCaseAndDeletedAtIsNull(String email);

    boolean existsByPhoneNumberAndDeletedAtIsNull(String phoneNumber);

    Optional<UserJpaEntity> findByEmailIgnoreCaseAndDeletedAtIsNull(String email);

    Optional<UserJpaEntity> findByIdAndDeletedAtIsNull(Long id);

    Optional<UserJpaEntity> findByPhoneNumberAndDeletedAtIsNull(String phoneNumber);

    boolean existsByPhoneNumberAndDeletedAtIsNullAndIdNot(
            String phoneNumber,
            Long id
    );
}
