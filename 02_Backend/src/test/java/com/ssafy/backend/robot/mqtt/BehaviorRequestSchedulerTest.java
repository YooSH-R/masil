package com.ssafy.backend.robot.mqtt;

import com.ssafy.backend.walk.application.WalkProposalCreationOutcome;
import com.ssafy.backend.walk.application.WalkProposalCreationService;
import com.ssafy.backend.walk.application.WalkProposalProducerProperties;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class BehaviorRequestSchedulerTest {

    private RobotMqttStore store;
    private WalkProposalCreationService walkProposalCreationService;
    private WalkProposalProducerProperties walkProposalProperties;
    private ApplicationEventPublisher eventPublisher;
    private BehaviorRequestTransactionWorker transactionWorker;
    private BehaviorRequestScheduler scheduler;

    @BeforeEach
    void setUp() {
        store = mock(RobotMqttStore.class);
        walkProposalCreationService = mock(WalkProposalCreationService.class);
        walkProposalProperties = new WalkProposalProducerProperties();
        eventPublisher = mock(ApplicationEventPublisher.class);
        transactionWorker = new BehaviorRequestTransactionWorker(
                store,
                walkProposalCreationService,
                walkProposalProperties,
                eventPublisher
        );
        scheduler = new BehaviorRequestScheduler(transactionWorker);
    }

    @Test
    void usesShorterInteractionIntervalForHigherAffinity() {
        assertEquals(Duration.ofHours(24), scheduler.interactionInterval(10));
        assertEquals(Duration.ofHours(12), scheduler.interactionInterval(30));
        assertEquals(Duration.ofHours(6), scheduler.interactionInterval(50));
        assertEquals(Duration.ofHours(4), scheduler.interactionInterval(70));
        assertEquals(Duration.ofHours(3), scheduler.interactionInterval(90));
    }

    @Test
    void createsAndQueuesDueInteractionRequest() {
        Instant now = Instant.parse("2026-07-30T12:00:00Z");
        RobotMqttStore.RequestCandidate candidate =
                new RobotMqttStore.RequestCandidate(
                        1L,
                        "device-001",
                        90,
                        now.minus(Duration.ofHours(4)),
                        80,
                        "IDLE",
                        now,
                        now
                );
        when(store.findRequestCandidates()).thenReturn(List.of(candidate));
        when(store.findPendingRequests(now)).thenReturn(List.of());
        when(store.hasOpenRequest(
                1L,
                BehaviorRequestType.INTERACTION_REQUEST
        )).thenReturn(false);
        when(store.createRequest(
                eq(candidate),
                eq(BehaviorRequestType.INTERACTION_REQUEST),
                any(String.class),
                eq(now),
                eq(now.plus(Duration.ofMinutes(30)))
        )).thenAnswer(invocation -> new BehaviorRequestMessage(
                java.util.UUID.randomUUID(),
                "1.0",
                "device-001",
                BehaviorRequestType.INTERACTION_REQUEST,
                invocation.getArgument(2),
                now,
                now.plus(Duration.ofMinutes(30))
        ));
        List<BehaviorRequestMessage> queued =
                scheduler.publishDueRequests(now);

        assertEquals(1, queued.size());
        verify(store).expireRequests(now);
        verifyNoInteractions(walkProposalCreationService);
        verify(eventPublisher).publishEvent(
                new BehaviorRequestPublishEvent(queued.get(0), now)
        );
    }

    @Test
    void doesNotCreateRequestsWhileRobotIsSleeping() {
        Instant now = Instant.parse("2026-07-30T12:00:00Z");
        walkProposalProperties.setSleepingModes(Set.of("NAP"));
        RobotMqttStore.RequestCandidate sleeping =
                new RobotMqttStore.RequestCandidate(
                        1L,
                        "device-001",
                        90,
                        now.minus(Duration.ofHours(10)),
                        10,
                        " nap ",
                        now.minus(Duration.ofDays(4)),
                        now.minus(Duration.ofDays(2))
                );
        when(store.findRequestCandidates()).thenReturn(List.of(sleeping));
        when(store.findPendingRequests(now)).thenReturn(List.of());

        List<BehaviorRequestMessage> published =
                scheduler.publishDueRequests(now);

        assertEquals(0, published.size());
        verify(store).expireRequests(now);
        verifyNoInteractions(walkProposalCreationService);
    }

    @ParameterizedTest
    @EnumSource(
            value = WalkProposalCreationOutcome.class,
            names = {"CREATED", "ALREADY_PENDING"}
    )
    void queuesWalkRequestOnlyAfterUsableProposalIsConfirmed(
            WalkProposalCreationOutcome outcome
    ) {
        Instant now = Instant.parse("2026-07-30T12:00:00Z");
        walkProposalProperties.setDueAfter(Duration.ofHours(48));
        walkProposalProperties.setProposalTtl(Duration.ofMinutes(45));
        RobotMqttStore.RequestCandidate candidate =
                new RobotMqttStore.RequestCandidate(
                        1L,
                        "device-001",
                        50,
                        now,
                        80,
                        "IDLE",
                        now.minus(Duration.ofHours(48)),
                        now
                );
        BehaviorRequestMessage request = new BehaviorRequestMessage(
                java.util.UUID.randomUUID(),
                "1.0",
                "device-001",
                BehaviorRequestType.WALK_REQUEST,
                "walk",
                now,
                now.plus(Duration.ofMinutes(45))
        );
        when(store.findRequestCandidates()).thenReturn(List.of(candidate));
        when(store.findPendingRequests(now)).thenReturn(List.of());
        when(store.hasOpenRequest(
                1L,
                BehaviorRequestType.WALK_REQUEST
        )).thenReturn(false);
        when(store.createRequest(
                eq(candidate),
                eq(BehaviorRequestType.WALK_REQUEST),
                any(String.class),
                eq(now),
                eq(now.plus(Duration.ofMinutes(45)))
        )).thenReturn(request);
        when(walkProposalCreationService.createIfDueForRobot(1L, now))
                .thenReturn(outcome);

        List<BehaviorRequestMessage> queued =
                scheduler.publishDueRequests(now);

        assertEquals(List.of(request), queued);
        var persistenceOrder = inOrder(walkProposalCreationService, store);
        persistenceOrder.verify(walkProposalCreationService)
                .createIfDueForRobot(1L, now);
        persistenceOrder.verify(store).createRequest(
                eq(candidate),
                eq(BehaviorRequestType.WALK_REQUEST),
                any(String.class),
                eq(now),
                eq(now.plus(Duration.ofMinutes(45)))
        );
        verify(eventPublisher).publishEvent(
                new BehaviorRequestPublishEvent(request, now)
        );
    }

    @ParameterizedTest
    @EnumSource(
            value = WalkProposalCreationOutcome.class,
            names = {"CREATED", "ALREADY_PENDING"},
            mode = EnumSource.Mode.EXCLUDE
    )
    void doesNotQueueWalkRequestWithoutUsableProposal(
            WalkProposalCreationOutcome outcome
    ) {
        Instant now = Instant.parse("2026-07-30T12:00:00Z");
        RobotMqttStore.RequestCandidate candidate =
                new RobotMqttStore.RequestCandidate(
                        1L,
                        "device-001",
                        50,
                        now,
                        80,
                        "IDLE",
                        now.minus(Duration.ofHours(72)),
                        now
                );
        when(store.findRequestCandidates()).thenReturn(List.of(candidate));
        when(store.findPendingRequests(now)).thenReturn(List.of());
        when(store.hasOpenRequest(
                1L,
                BehaviorRequestType.WALK_REQUEST
        )).thenReturn(false);
        when(walkProposalCreationService.createIfDueForRobot(1L, now))
                .thenReturn(outcome);

        List<BehaviorRequestMessage> queued =
                scheduler.publishDueRequests(now);

        assertEquals(List.of(), queued);
        verify(walkProposalCreationService).createIfDueForRobot(1L, now);
        verify(store, never()).createRequest(
                eq(candidate),
                eq(BehaviorRequestType.WALK_REQUEST),
                any(String.class),
                eq(now),
                any(Instant.class)
        );
        verifyNoInteractions(eventPublisher);
    }

    @Test
    void skipsWalkProposalAndRequestDuringTerminalRequestCooldown() {
        Instant now = Instant.parse("2026-07-30T12:00:00Z");
        walkProposalProperties.setRetryCooldown(Duration.ofHours(4));
        RobotMqttStore.RequestCandidate candidate =
                new RobotMqttStore.RequestCandidate(
                        1L,
                        "device-001",
                        50,
                        now,
                        80,
                        "IDLE",
                        now.minus(Duration.ofHours(72)),
                        now
                );
        when(store.findRequestCandidates()).thenReturn(List.of(candidate));
        when(store.findPendingRequests(now)).thenReturn(List.of());
        when(store.hasOpenRequest(
                1L,
                BehaviorRequestType.WALK_REQUEST
        )).thenReturn(false);
        when(store.hasRecentRequest(
                1L,
                BehaviorRequestType.WALK_REQUEST,
                now.minus(Duration.ofHours(4))
        )).thenReturn(true);

        List<BehaviorRequestMessage> queued =
                scheduler.publishDueRequests(now);

        assertEquals(List.of(), queued);
        verify(store).lockRequestGeneration(1L);
        verifyNoInteractions(walkProposalCreationService);
        verify(store, never()).createRequest(
                eq(candidate),
                eq(BehaviorRequestType.WALK_REQUEST),
                any(String.class),
                eq(now),
                any(Instant.class)
        );
        verifyNoInteractions(eventPublisher);
    }

    @Test
    void queuesPreviouslyUnpublishedRequestForRetry() {
        Instant now = Instant.parse("2026-07-30T12:00:00Z");
        BehaviorRequestMessage pending = new BehaviorRequestMessage(
                java.util.UUID.randomUUID(),
                "1.0",
                "device-001",
                BehaviorRequestType.WALK_REQUEST,
                "함께 산책해요.",
                now.minusSeconds(60),
                now.plusSeconds(600)
        );
        when(store.findPendingRequests(now)).thenReturn(List.of(pending));
        when(store.findRequestCandidates()).thenReturn(List.of());

        List<BehaviorRequestMessage> queued =
                scheduler.publishDueRequests(now);

        assertEquals(List.of(pending), queued);
        verifyNoInteractions(walkProposalCreationService);
        verify(eventPublisher).publishEvent(
                new BehaviorRequestPublishEvent(pending, now)
        );
    }

    @Test
    void continuesWithNextRobotWhenOneCandidateFails() {
        Instant now = Instant.parse("2026-07-30T12:00:00Z");
        RobotMqttStore.RequestCandidate failing = candidate(1L, "device-001");
        RobotMqttStore.RequestCandidate succeeding = candidate(2L, "device-002");
        BehaviorRequestMessage pending = request(
                "device-pending",
                BehaviorRequestType.PLAY_REQUEST,
                now
        );
        BehaviorRequestMessage created = request(
                "device-002",
                BehaviorRequestType.WALK_REQUEST,
                now
        );
        BehaviorRequestTransactionWorker worker = mock(
                BehaviorRequestTransactionWorker.class
        );
        BehaviorRequestScheduler isolatedScheduler =
                new BehaviorRequestScheduler(worker);
        when(worker.prepareCycle(now)).thenReturn(List.of(pending));
        when(worker.findRequestCandidates())
                .thenReturn(List.of(failing, succeeding));
        when(worker.processCandidate(failing, now))
                .thenThrow(new IllegalStateException("candidate failure"));
        when(worker.processCandidate(succeeding, now))
                .thenReturn(List.of(created));

        List<BehaviorRequestMessage> queued =
                isolatedScheduler.publishDueRequests(now);

        assertEquals(List.of(pending, created), queued);
        verify(worker).processCandidate(failing, now);
        verify(worker).processCandidate(succeeding, now);
    }

    @Test
    void usesIndependentTransactionsForPreparationAndEachCandidate()
            throws NoSuchMethodException {
        Transactional preparation = BehaviorRequestTransactionWorker.class
                .getMethod("prepareCycle", Instant.class)
                .getAnnotation(Transactional.class);
        Transactional candidate = BehaviorRequestTransactionWorker.class
                .getMethod(
                        "processCandidate",
                        RobotMqttStore.RequestCandidate.class,
                        Instant.class
                )
                .getAnnotation(Transactional.class);

        assertNotNull(preparation);
        assertNotNull(candidate);
        assertEquals(Propagation.REQUIRES_NEW, preparation.propagation());
        assertEquals(Propagation.REQUIRES_NEW, candidate.propagation());
    }

    private RobotMqttStore.RequestCandidate candidate(
            long robotId,
            String deviceId
    ) {
        return new RobotMqttStore.RequestCandidate(
                robotId,
                deviceId,
                50,
                Instant.EPOCH,
                80,
                "IDLE",
                Instant.EPOCH,
                Instant.EPOCH
        );
    }

    private BehaviorRequestMessage request(
            String deviceId,
            BehaviorRequestType type,
            Instant now
    ) {
        return new BehaviorRequestMessage(
                java.util.UUID.randomUUID(),
                "1.0",
                deviceId,
                type,
                "request",
                now,
                now.plusSeconds(600)
        );
    }
}
