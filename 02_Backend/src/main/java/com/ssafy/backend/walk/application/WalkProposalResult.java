package com.ssafy.backend.walk.application;

import com.ssafy.backend.walk.domain.WalkProposalStatus;

import java.time.Instant;

public record WalkProposalResult(
        Long proposalId,
        Long petId,
        Long robotId,
        String message,
        String reason,
        WalkProposalStatus status,
        Instant proposedAt,
        Instant expiresAt,
        Instant respondedAt
) {
}
