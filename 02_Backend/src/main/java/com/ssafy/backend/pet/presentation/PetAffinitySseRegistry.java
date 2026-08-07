package com.ssafy.backend.pet.presentation;

import com.ssafy.backend.pet.application.PetAffinityChangedEvent;
import com.ssafy.backend.pet.application.PetAffinitySnapshot;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.io.IOException;
import java.time.Instant;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;

@Component
public class PetAffinitySseRegistry {

    private static final Logger log = LoggerFactory.getLogger(
            PetAffinitySseRegistry.class
    );
    private static final long RECONNECT_TIME_MS = 5_000L;

    private final ConcurrentMap<Long, Set<SseEmitter>> emitters =
            new ConcurrentHashMap<>();
    private final long timeoutMs;

    public PetAffinitySseRegistry(
            @Value("${pet.affinity.sse.timeout-ms:1800000}") long timeoutMs
    ) {
        if (timeoutMs <= 0) {
            throw new IllegalArgumentException(
                    "pet.affinity.sse.timeout-ms must be positive"
            );
        }
        this.timeoutMs = timeoutMs;
    }

    public SseEmitter subscribe(PetAffinitySnapshot snapshot) {
        SseEmitter emitter = new SseEmitter(timeoutMs);
        long petId = snapshot.petId();
        emitters.computeIfAbsent(
                petId,
                ignored -> ConcurrentHashMap.newKeySet()
        ).add(emitter);
        emitter.onCompletion(() -> remove(petId, emitter));
        emitter.onTimeout(() -> {
            remove(petId, emitter);
            emitter.complete();
        });
        emitter.onError(ignored -> remove(petId, emitter));

        if (!send(
                petId,
                emitter,
                SseEmitter.event()
                        .id("snapshot-" + snapshot.updatedAt().toEpochMilli())
                        .name("affinity-snapshot")
                        .reconnectTime(RECONNECT_TIME_MS)
                        .data(PetAffinitySsePayload.snapshot(snapshot))
        )) {
            emitter.complete();
        }
        return emitter;
    }

    public void broadcast(PetAffinityChangedEvent event) {
        Set<SseEmitter> petEmitters = emitters.get(event.petId());
        if (petEmitters == null || petEmitters.isEmpty()) {
            return;
        }
        for (SseEmitter emitter : Set.copyOf(petEmitters)) {
            send(
                    event.petId(),
                    emitter,
                    SseEmitter.event()
                            .id(event.eventMessageId().toString())
                            .name("affinity-changed")
                            .reconnectTime(RECONNECT_TIME_MS)
                            .data(PetAffinitySsePayload.changed(event))
            );
        }
    }

    @Scheduled(
            fixedDelayString = "${pet.affinity.sse.heartbeat-ms:20000}",
            initialDelayString = "${pet.affinity.sse.heartbeat-ms:20000}"
    )
    public void heartbeat() {
        for (var entry : emitters.entrySet()) {
            long petId = entry.getKey();
            for (SseEmitter emitter : Set.copyOf(entry.getValue())) {
                send(
                        petId,
                        emitter,
                        SseEmitter.event().comment(
                                "heartbeat " + Instant.now()
                        )
                );
            }
        }
    }

    public int activeConnectionCount(long petId) {
        Set<SseEmitter> petEmitters = emitters.get(petId);
        return petEmitters == null ? 0 : petEmitters.size();
    }

    public void disconnect(long petId) {
        Set<SseEmitter> petEmitters = emitters.remove(petId);
        if (petEmitters == null) {
            return;
        }
        for (SseEmitter emitter : Set.copyOf(petEmitters)) {
            try {
                emitter.complete();
            } catch (IllegalStateException ignored) {
                // The connection was already completed concurrently.
            }
        }
        petEmitters.clear();
    }

    private boolean send(
            long petId,
            SseEmitter emitter,
            SseEmitter.SseEventBuilder event
    ) {
        try {
            synchronized (emitter) {
                emitter.send(event);
            }
            return true;
        } catch (IOException | IllegalStateException exception) {
            remove(petId, emitter);
            try {
                emitter.completeWithError(exception);
            } catch (IllegalStateException ignored) {
                // The connection was already completed concurrently.
            }
            log.debug(
                    "호감도 SSE 연결을 정리했습니다. petId={}",
                    petId,
                    exception
            );
            return false;
        }
    }

    private void remove(long petId, SseEmitter emitter) {
        Set<SseEmitter> petEmitters = emitters.get(petId);
        if (petEmitters == null) {
            return;
        }
        petEmitters.remove(emitter);
        if (petEmitters.isEmpty()) {
            emitters.remove(petId, petEmitters);
        }
    }
}
