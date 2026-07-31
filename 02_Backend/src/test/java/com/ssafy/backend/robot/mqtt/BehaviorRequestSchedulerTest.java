package com.ssafy.backend.robot.mqtt;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.context.ApplicationEventPublisher;

import java.time.Duration;
import java.time.Instant;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class BehaviorRequestSchedulerTest {

    private RobotMqttStore store;
    private ApplicationEventPublisher eventPublisher;
    private BehaviorRequestScheduler scheduler;

    @BeforeEach
    void setUp() {
        store = mock(RobotMqttStore.class);
        eventPublisher = mock(ApplicationEventPublisher.class);
        scheduler = new BehaviorRequestScheduler(
                store,
                eventPublisher
        );
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
        verify(eventPublisher).publishEvent(
                new BehaviorRequestPublishEvent(queued.get(0), now)
        );
    }

    @Test
    void doesNotCreateRequestsWhileRobotIsSleeping() {
        Instant now = Instant.parse("2026-07-30T12:00:00Z");
        RobotMqttStore.RequestCandidate sleeping =
                new RobotMqttStore.RequestCandidate(
                        1L,
                        "device-001",
                        90,
                        now.minus(Duration.ofHours(10)),
                        10,
                        "SLEEPING",
                        now.minus(Duration.ofDays(4)),
                        now.minus(Duration.ofDays(2))
                );
        when(store.findRequestCandidates()).thenReturn(List.of(sleeping));
        when(store.findPendingRequests(now)).thenReturn(List.of());

        List<BehaviorRequestMessage> published =
                scheduler.publishDueRequests(now);

        assertEquals(0, published.size());
        verify(store).expireRequests(now);
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
        verify(eventPublisher).publishEvent(
                new BehaviorRequestPublishEvent(pending, now)
        );
    }
}
