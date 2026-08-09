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

    /**
     * 앱에서 시작한 산책을 앱이 끝낸다.
     *
     * <p>기기 경로와 같은 두 단계(PROCESSING 전환 → 완료)를 밟는다. 두 단계를
     * 나누는 이유도 같다. 종료 시각을 먼저 확정해야 그 뒤에 늦게 도착한 좌표를
     * 받아줄지 판단할 수 있다.
     */
    public WalkResult endWalkByUser(
            Long userId,
            Long walkId,
            Instant reportedAt
    ) {
        WalkCommandService.EndPreparation preparation =
                commandService.prepareEndByUser(userId, walkId, reportedAt);
        if (preparation.completed()) {
            return preparation.walk();
        }

        return commandService.completeEndByUser(userId, walkId);
    }
}
