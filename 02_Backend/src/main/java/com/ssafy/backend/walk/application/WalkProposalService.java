package com.ssafy.backend.walk.application;

import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import com.ssafy.backend.walk.domain.WalkProposalStatus;
import org.springframework.stereotype.Service;

import java.time.Instant;

@Service
public class WalkProposalService {

    private final WalkCommandService commandService;

    public WalkProposalService(WalkCommandService commandService) {
        this.commandService = commandService;
    }

    public void respond(
            Long userId,
            Long proposalId,
            WalkProposalStatus response,
            Instant reportedAt
    ) {
        WalkCommandService.ProposalResponseOutcome outcome =
                commandService.respondToProposal(
                        userId,
                        proposalId,
                        response,
                        reportedAt
                );
        if (outcome == WalkCommandService.ProposalResponseOutcome.EXPIRED) {
            throw new BusinessException(ErrorCode.WALK_PROPOSAL_EXPIRED);
        }
    }
}
