package com.ssafy.backend.pet;

import com.ssafy.backend.pet.application.PetCreatedResult;
import com.ssafy.backend.pet.application.PetService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.jdbc.core.JdbcTemplate;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.postgresql.PostgreSQLContainer;

import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

@Testcontainers(disabledWithoutDocker = true)
@SpringBootTest(properties = {
        "spring.jpa.hibernate.ddl-auto=validate",
        "spring.sql.init.mode=always",
        "spring.sql.init.schema-locations=file:../06_Infra/postgres/init/001_schema.sql",
        "solapi.api-key=test-api-key",
        "solapi.secret-key=test-secret-key",
        "solapi.sender=01000000000"
})
class PetPostgreSqlIntegrationTest {

    @Container
    @ServiceConnection
    static final PostgreSQLContainer POSTGRES =
            new PostgreSQLContainer("postgres:17-alpine");

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private PetService petService;

    @BeforeEach
    void resetData() {
        jdbcTemplate.execute(
                "TRUNCATE TABLE users RESTART IDENTITY CASCADE"
        );
        jdbcTemplate.update(
                """
                INSERT INTO users (id, nickname)
                VALUES (1, 'owner')
                """
        );
    }

    @Test
    void concurrentRequestsReturnSamePetAndRollbackDuplicateRows()
            throws Exception {
        ExecutorService executor = Executors.newFixedThreadPool(2);
        CountDownLatch ready = new CountDownLatch(2);
        CountDownLatch start = new CountDownLatch(1);

        try {
            List<Future<PetCreatedResult>> futures = List.of(
                    executor.submit(() -> createAfterSignal(ready, start)),
                    executor.submit(() -> createAfterSignal(ready, start))
            );

            assertTrue(ready.await(5, TimeUnit.SECONDS));
            start.countDown();

            PetCreatedResult first = futures.get(0)
                    .get(10, TimeUnit.SECONDS);
            PetCreatedResult second = futures.get(1)
                    .get(10, TimeUnit.SECONDS);

            assertEquals(first.petId(), second.petId());
        } finally {
            start.countDown();
            executor.shutdownNow();
        }

        assertEquals(1, countRows("pets"));
        assertEquals(1, countRows("pet_affinity_states"));
        assertEquals(1, countRows("pet_creation_requests"));
    }

    private PetCreatedResult createAfterSignal(
            CountDownLatch ready,
            CountDownLatch start
    ) throws InterruptedException {
        ready.countDown();
        start.await();
        return petService.create(
                1L,
                "postgres-concurrent-create",
                "몽이"
        );
    }

    private int countRows(String tableName) {
        return jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM " + tableName,
                Integer.class
        );
    }
}
