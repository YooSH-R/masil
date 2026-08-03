package com.ssafy.backend.walk.application;

public enum WalkProposalCreationOutcome {
    CREATED,
    ACTIVE_PAIRING_NOT_FOUND,
    ROBOT_SLEEPING,
    ALREADY_PENDING,
    EXPIRED_PENDING_AWAITING_CLEANUP,
    ACCEPTED_PROPOSAL_AWAITING_WALK,
    WALK_IN_PROGRESS,
    RECENT_WALK
}
