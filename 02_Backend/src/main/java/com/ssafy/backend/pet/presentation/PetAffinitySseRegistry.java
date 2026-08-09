package com.ssafy.backend.pet.presentation;

import com.ssafy.backend.pet.application.PetAffinityChangedEvent;
import com.ssafy.backend.pet.application.PetAffinitySnapshot;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.io.IOException;
import java.time.Instant;
import java.util.ArrayDeque;
import java.util.Queue;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.concurrent.Executor;
import java.util.concurrent.RejectedExecutionException;
import java.util.function.Consumer;

@Component
public class PetAffinitySseRegistry {

    private static final Logger log = LoggerFactory.getLogger(
            PetAffinitySseRegistry.class
    );
    private static final long RECONNECT_TIME_MS = 5_000L;

    private final ConcurrentMap<Long, Set<SseEmitter>> emitters =
            new ConcurrentHashMap<>();
    private final ConcurrentMap<SseEmitter, SerialExecutor> sendExecutors =
            new ConcurrentHashMap<>();
    private final long timeoutMs;
    private final Executor sendExecutor;

    public PetAffinitySseRegistry(
            @Value("${pet.affinity.sse.timeout-ms:1800000}") long timeoutMs,
            @Qualifier("petAffinitySseExecutor") Executor sendExecutor
    ) {
        if (timeoutMs <= 0) {
            throw new IllegalArgumentException(
                    "pet.affinity.sse.timeout-ms must be positive"
            );
        }
        this.timeoutMs = timeoutMs;
        this.sendExecutor = sendExecutor;
    }

    public SseEmitter subscribe(PetAffinitySnapshot snapshot) {
        SseEmitter emitter = new SseEmitter(timeoutMs);
        long petId = snapshot.petId();
        emitters.compute(petId, (ignored, petEmitters) -> {
            Set<SseEmitter> result = petEmitters;
            if (result == null) {
                result = ConcurrentHashMap.newKeySet();
            }
            result.add(emitter);
            return result;
        });
        sendExecutors.put(emitter, new SerialExecutor(
                sendExecutor,
                exception -> reject(petId, emitter, exception)
        ));
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
            sendAsync(
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
                sendAsync(
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
            sendExecutors.remove(emitter);
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

    private void sendAsync(
            long petId,
            SseEmitter emitter,
            SseEmitter.SseEventBuilder event
    ) {
        SerialExecutor serialExecutor = sendExecutors.get(emitter);
        if (serialExecutor == null) {
            return;
        }
        serialExecutor.execute(() -> send(petId, emitter, event));
    }

    private void remove(long petId, SseEmitter emitter) {
        sendExecutors.remove(emitter);
        emitters.computeIfPresent(petId, (ignored, petEmitters) -> {
            petEmitters.remove(emitter);
            return petEmitters.isEmpty() ? null : petEmitters;
        });
    }

    private void reject(
            long petId,
            SseEmitter emitter,
            RejectedExecutionException exception
    ) {
        remove(petId, emitter);
        try {
            emitter.completeWithError(exception);
        } catch (IllegalStateException ignored) {
            // The connection was already completed concurrently.
        }
        log.warn(
                "Affinity SSE delivery was rejected; reconnect required. "
                        + "petId={}",
                petId
        );
    }

    private static final class SerialExecutor implements Executor {

        private final Queue<Runnable> tasks = new ArrayDeque<>();
        private final Executor executor;
        private final Consumer<RejectedExecutionException> rejectionHandler;
        private Runnable active;

        private SerialExecutor(
                Executor executor,
                Consumer<RejectedExecutionException> rejectionHandler
        ) {
            this.executor = executor;
            this.rejectionHandler = rejectionHandler;
        }

        @Override
        public void execute(Runnable command) {
            Runnable next = null;
            synchronized (this) {
                tasks.offer(() -> {
                    try {
                        command.run();
                    } finally {
                        scheduleNext();
                    }
                });
                if (active == null) {
                    active = tasks.poll();
                    next = active;
                }
            }
            if (next != null) {
                dispatch(next);
            }
        }

        private void scheduleNext() {
            Runnable next;
            synchronized (this) {
                active = tasks.poll();
                next = active;
            }
            if (next != null) {
                dispatch(next);
            }
        }

        private void dispatch(Runnable next) {
            try {
                executor.execute(next);
            } catch (RejectedExecutionException exception) {
                synchronized (this) {
                    active = null;
                    tasks.clear();
                }
                rejectionHandler.accept(exception);
            }
        }
    }
}
