package com.ssafy.backend.robot.mqtt;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

@Component
@ConditionalOnProperty(
        name = {"mqtt.enabled", "mqtt.request-scheduler.enabled"},
        havingValue = "true"
)
public class BehaviorRequestScheduler {

    private static final Logger log = LoggerFactory.getLogger(
            BehaviorRequestScheduler.class
    );

    private final BehaviorRequestTransactionWorker transactionWorker;

    public BehaviorRequestScheduler(
            BehaviorRequestTransactionWorker transactionWorker
    ) {
        this.transactionWorker = transactionWorker;
    }

    @Scheduled(
            fixedDelayString = "${mqtt.request-scheduler.fixed-delay-ms:60000}",
            initialDelayString =
                    "${mqtt.request-scheduler.initial-delay-ms:60000}"
    )
    public void publishDueRequests() {
        publishDueRequests(Instant.now());
    }

    List<BehaviorRequestMessage> publishDueRequests(Instant now) {
        List<BehaviorRequestMessage> pending;
        try {
            pending = transactionWorker.prepareCycle(now);
        } catch (RuntimeException exception) {
            log.error("행동 요청 스케줄 준비에 실패했습니다.", exception);
            return List.of();
        }

        List<BehaviorRequestMessage> queued = new ArrayList<>(pending);
        List<RobotMqttStore.RequestCandidate> candidates;
        try {
            candidates = transactionWorker.findRequestCandidates();
        } catch (RuntimeException exception) {
            log.error("행동 요청 후보 조회에 실패했습니다.", exception);
            return List.copyOf(queued);
        }
        for (RobotMqttStore.RequestCandidate candidate
                : candidates) {
            try {
                queued.addAll(transactionWorker.processCandidate(candidate, now));
            } catch (RuntimeException exception) {
                log.error(
                        "로봇 행동 요청 생성에 실패해 이번 주기에서 건너뜁니다. robotId={}, deviceId={}",
                        candidate.robotId(),
                        candidate.deviceId(),
                        exception
                );
            }
        }
        return List.copyOf(queued);
    }

    Duration interactionInterval(int affinityScore) {
        return transactionWorker.interactionInterval(affinityScore);
    }

    boolean isSleeping(String mode) {
        return transactionWorker.isSleeping(mode);
    }
}
