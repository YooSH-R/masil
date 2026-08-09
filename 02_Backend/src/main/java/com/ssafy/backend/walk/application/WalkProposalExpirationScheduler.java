package com.ssafy.backend.walk.application;

import com.ssafy.backend.walk.infrastructure.persistence.SpringDataWalkProposalRepository;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;

@Component
@ConditionalOnProperty(
        name = "walk.proposal-expiration-scheduler-enabled",
        havingValue = "true",
        matchIfMissing = true
)
public class WalkProposalExpirationScheduler {

    private final SpringDataWalkProposalRepository proposalRepository;
    private final Clock clock;

    public WalkProposalExpirationScheduler(
            SpringDataWalkProposalRepository proposalRepository,
            Clock clock
    ) {
        this.proposalRepository = proposalRepository;
        this.clock = clock;
    }

    @Scheduled(fixedDelayString = "${walk.proposal-expiration-delay-ms:60000}")
    @Transactional
    public void expireDueProposals() {
        proposalRepository.expireAllPendingProposals(clock.instant());
    }
}
