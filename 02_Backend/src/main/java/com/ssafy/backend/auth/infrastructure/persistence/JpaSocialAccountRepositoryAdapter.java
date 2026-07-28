package com.ssafy.backend.auth.infrastructure.persistence;

import com.ssafy.backend.auth.application.port.out.SocialAccountRepository;
import com.ssafy.backend.auth.domain.SocialPrincipal;
import com.ssafy.backend.auth.domain.SocialProvider;
import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import com.ssafy.backend.user.domain.User;
import com.ssafy.backend.user.infrastructure.persistence.JpaUserRepositoryAdapter;
import com.ssafy.backend.user.infrastructure.persistence.SpringDataUserRepository;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public class JpaSocialAccountRepositoryAdapter implements SocialAccountRepository {

    private final SpringDataSocialAccountRepository socialAccountRepository;
    private final SpringDataUserRepository userRepository;

    public JpaSocialAccountRepositoryAdapter(
            SpringDataSocialAccountRepository socialAccountRepository,
            SpringDataUserRepository userRepository
    ) {
        this.socialAccountRepository = socialAccountRepository;
        this.userRepository = userRepository;
    }

    @Override
    public Optional<User> findUser(SocialProvider provider, String providerUserId) {
        return socialAccountRepository
                .findByProviderAndProviderUserId(provider, providerUserId)
                .flatMap(account -> userRepository.findById(account.getUserId()))
                .map(JpaUserRepositoryAdapter::toDomain);
    }

    @Override
    public boolean exists(SocialProvider provider, String providerUserId) {
        return socialAccountRepository.existsByProviderAndProviderUserId(
                provider,
                providerUserId
        );
    }

    @Override
    public void save(Long userId, SocialPrincipal principal) {
        try {
            socialAccountRepository.saveAndFlush(new SocialAccountJpaEntity(
                    userId,
                    principal.provider(),
                    principal.providerUserId(),
                    principal.email()
            ));
        } catch (DataIntegrityViolationException exception) {
            throw new BusinessException(ErrorCode.SOCIAL_ACCOUNT_ALREADY_LINKED);
        }
    }
}
