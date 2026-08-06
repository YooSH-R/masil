package com.ssafy.backend.walk.application;

import org.springframework.stereotype.Service;

import java.time.Instant;

@Service
public class WalkCompletionService {

    private final WalkCommandService commandService;

    public WalkCompletionService(WalkCommandService commandService) {
        this.commandService = commandService;
    }

    public WalkResult endWalk(
            Long robotId,
            String deviceId,
            Long walkId,
            Instant reportedAt
    ) {
        WalkCommandService.EndPreparation preparation = commandService.prepareEnd(
                robotId,
                walkId,
                reportedAt
        );
        if (preparation.completed()) {
            return preparation.walk();
        }

        return commandService.completeEnd(robotId, deviceId, walkId);
    }
}
