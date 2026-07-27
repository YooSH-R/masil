package com.ssafy.backend.auth.infrastructure.persistence;

import com.ssafy.backend.auth.application.port.out.SignupTicketRepository;
import com.ssafy.backend.auth.domain.SignupTicket;
import com.ssafy.backend.auth.domain.SocialPrincipal;
import org.springframework.stereotype.Repository;

import java.time.Instant;
import java.util.Optional;

@Repository
public class JpaSignupTicketRepositoryAdapter implements SignupTicketRepository {

    private final SpringDataSignupTicketRepository repository;

    public JpaSignupTicketRepositoryAdapter(SpringDataSignupTicketRepository repository) {
        this.repository = repository;
    }

    @Override
    public void save(
            String tokenHash,
            SocialPrincipal principal,
            String deviceId,
            Instant expiresAt
    ) {
        repository.save(new SignupTicketJpaEntity(
                tokenHash,
                principal.provider(),
                principal.providerUserId(),
                principal.email(),
                principal.suggestedNickname(),
                deviceId,
                expiresAt
        ));
    }

    @Override
    public Optional<SignupTicket> findByTokenHash(String tokenHash) {
        return repository.findByTokenHash(tokenHash).map(this::toDomain);
    }

    @Override
    public void markUsed(Long ticketId, Instant usedAt) {
        SignupTicketJpaEntity entity = repository.findById(ticketId)
                .orElseThrow();
        entity.markUsed(usedAt);
    }

    private SignupTicket toDomain(SignupTicketJpaEntity entity) {
        return new SignupTicket(
                entity.getId(),
                new SocialPrincipal(
                        entity.getProvider(),
                        entity.getProviderUserId(),
                        entity.getEmail(),
                        entity.getSuggestedNickname()
                ),
                entity.getDeviceId(),
                entity.getExpiresAt(),
                entity.getUsedAt()
        );
    }
}
