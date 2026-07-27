package com.ssafy.backend.user.infrastructure.persistence;

import com.ssafy.backend.user.application.port.out.UserRepository;
import com.ssafy.backend.user.domain.User;
import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Repository;

@Repository
public class JpaUserRepositoryAdapter implements UserRepository {

    private final SpringDataUserRepository repository;

    public JpaUserRepositoryAdapter(SpringDataUserRepository repository) {
        this.repository = repository;
    }

    @Override
    public boolean existsByNickname(String nickname) {
        return repository.existsByNicknameAndDeletedAtIsNull(nickname);
    }

    @Override
    public User save(User user) {
        try {
            UserJpaEntity saved = repository.saveAndFlush(new UserJpaEntity(
                    user.email(),
                    user.nickname(),
                    user.phoneNumber()
            ));
            return toDomain(saved);
        } catch (DataIntegrityViolationException exception) {
            throw new BusinessException(ErrorCode.NICKNAME_DUPLICATED);
        }
    }

    public static User toDomain(UserJpaEntity entity) {
        return new User(
                entity.getId(),
                entity.getEmail(),
                entity.getNickname(),
                entity.getPhoneNumber(),
                entity.getCreatedAt()
        );
    }
}
