package com.ssafy.backend.robot.mqtt;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.ObjectMapper;

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
    private RobotMqttPublisher publisher;
    private ObjectMapper objectMapper;
    private BehaviorRequestScheduler scheduler;

    @BeforeEach
    void setUp() {
        store = mock(RobotMqttStore.class);
        publisher = mock(RobotMqttPublisher.class);
        objectMapper = mock(ObjectMapper.class);
        scheduler = new BehaviorRequestScheduler(
                store,
                publisher,
                objectMapper
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
    void createsAndPublishesDueInteractionRequest() throws Exception {
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
        when(objectMapper.writeValueAsString(any())).thenReturn("{}");

        List<BehaviorRequestMessage> published =
                scheduler.publishDueRequests(now);

        assertEquals(1, published.size());
        verify(store).expireRequests(now);
        verify(publisher).publish(
                RobotMqttTopics.requests("device-001"),
                1,
                "{}"
        );
        verify(store).markRequestPublished(
                published.get(0).requestId(),
                now
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

        List<BehaviorRequestMessage> published =
                scheduler.publishDueRequests(now);

        assertEquals(0, published.size());
        verify(store).expireRequests(now);
    }
}
