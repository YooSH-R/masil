package com.ssafy.backend.auth.infrastructure.persistence;

import com.ssafy.backend.auth.domain.SocialProvider;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.List;

public interface SpringDataSocialAccountRepository
        extends JpaRepository<SocialAccountJpaEntity, Long> {

    Optional<SocialAccountJpaEntity> findByProviderAndProviderUserId(
            SocialProvider provider,
            String providerUserId
    );

    boolean existsByProviderAndProviderUserId(
            SocialProvider provider,
            String providerUserId
    );

    List<SocialAccountJpaEntity> findAllByUserIdOrderByIdAsc(Long userId);

    void deleteByUserId(Long userId);
}
