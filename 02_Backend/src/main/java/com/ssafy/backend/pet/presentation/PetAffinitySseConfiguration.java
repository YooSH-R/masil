package com.ssafy.backend.pet.presentation;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

import java.util.concurrent.Executor;

@Configuration
class PetAffinitySseConfiguration {

    @Bean(name = "petAffinitySseExecutor")
    Executor petAffinitySseExecutor(
            @Value("${pet.affinity.sse.executor.core-pool-size:4}")
            int corePoolSize,
            @Value("${pet.affinity.sse.executor.max-pool-size:16}")
            int maxPoolSize,
            @Value("${pet.affinity.sse.executor.queue-capacity:512}")
            int queueCapacity
    ) {
        if (corePoolSize <= 0 || maxPoolSize < corePoolSize) {
            throw new IllegalArgumentException(
                    "Invalid pet affinity SSE executor pool size"
            );
        }
        if (queueCapacity <= 0) {
            throw new IllegalArgumentException(
                    "pet affinity SSE executor queue capacity must be positive"
            );
        }

        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(corePoolSize);
        executor.setMaxPoolSize(maxPoolSize);
        executor.setQueueCapacity(queueCapacity);
        executor.setThreadNamePrefix("affinity-sse-");
        executor.setWaitForTasksToCompleteOnShutdown(true);
        executor.setAwaitTerminationSeconds(5);
        executor.initialize();
        return executor;
    }
}
