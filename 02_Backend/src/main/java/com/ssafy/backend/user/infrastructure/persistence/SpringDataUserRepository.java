package com.ssafy.backend.user.infrastructure.persistence;

import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;

public interface SpringDataUserRepository extends JpaRepository<UserJpaEntity, Long> {

    boolean existsByNicknameAndDeletedAtIsNull(String nickname);

    boolean existsByEmailIgnoreCaseAndDeletedAtIsNull(String email);

    boolean existsByPhoneNumberAndDeletedAtIsNull(String phoneNumber);

    Optional<UserJpaEntity> findByEmailIgnoreCaseAndDeletedAtIsNull(String email);

    Optional<UserJpaEntity> findByIdAndDeletedAtIsNull(Long id);

    Optional<UserJpaEntity> findByPhoneNumberAndDeletedAtIsNull(String phoneNumber);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select user from UserJpaEntity user where user.id = :id")
    Optional<UserJpaEntity> findByIdForUpdate(@Param("id") Long id);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
            select user
            from UserJpaEntity user
            where user.phoneNumber = :phoneNumber
              and user.deletedAt is null
            """)
    Optional<UserJpaEntity> findActiveByPhoneNumberForUpdate(
            @Param("phoneNumber") String phoneNumber
    );

    boolean existsByNicknameAndDeletedAtIsNullAndIdNot(String nickname, Long id);

    boolean existsByPhoneNumberAndDeletedAtIsNullAndIdNot(
            String phoneNumber,
            Long id
    );
}
