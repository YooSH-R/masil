package com.ssafy.backend.user.infrastructure.persistence;

import com.ssafy.backend.user.application.port.out.UserRepository;
import com.ssafy.backend.user.domain.User;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public class JpaUserRepositoryAdapter implements UserRepository {

    private final SpringDataUserRepository repository;

    public JpaUserRepositoryAdapter(SpringDataUserRepository repository) {
        this.repository = repository;
    }

    @Override
    public boolean existsByEmail(String email) {
        return repository.existsByEmailIgnoreCaseAndDeletedAtIsNull(email);
    }

    @Override
    public boolean existsByPhoneNumber(String phoneNumber) {
        return repository.existsByPhoneNumberAndDeletedAtIsNull(phoneNumber);
    }

    @Override
    public Optional<User> findByEmail(String email) {
        return repository.findByEmailIgnoreCaseAndDeletedAtIsNull(email)
                .map(JpaUserRepositoryAdapter::toDomain);
    }

    @Override
    public Optional<User> findById(Long id) {
        return repository.findById(id).map(JpaUserRepositoryAdapter::toDomain);
    }

    @Override
    public User save(User user) {
        UserJpaEntity saved = repository.saveAndFlush(new UserJpaEntity(
                user.email(),
                user.passwordHash(),
                user.nickname(),
                user.phoneNumber(),
                user.phoneVerifiedAt()
        ));
        return toDomain(saved);
    }

    public static User toDomain(UserJpaEntity entity) {
        return new User(
                entity.getId(),
                entity.getEmail(),
                entity.getPasswordHash(),
                entity.getNickname(),
                entity.getPhoneNumber(),
                entity.getPhoneVerifiedAt(),
                entity.getCreatedAt()
        );
    }
}
