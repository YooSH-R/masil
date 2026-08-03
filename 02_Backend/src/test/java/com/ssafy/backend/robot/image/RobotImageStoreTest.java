package com.ssafy.backend.robot.image;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

class RobotImageStoreTest {

    @Test
    void convertsUploadInstantsToSqlTimestamps() {
        JdbcTemplate jdbcTemplate = mock(JdbcTemplate.class);
        RobotImageStore store = new RobotImageStore(jdbcTemplate);
        UUID imageId = UUID.randomUUID();
        Instant capturedAt = Instant.parse("2026-07-31T00:00:00Z");
        Instant expiresAt = Instant.parse("2026-07-31T00:05:00Z");

        store.createPending(
                imageId,
                1L,
                "robot-images/device-001/test.jpg",
                "image/jpeg",
                1024L,
                capturedAt,
                expiresAt
        );

        ArgumentCaptor<Object[]> arguments =
                ArgumentCaptor.forClass(Object[].class);
        verify(jdbcTemplate).update(anyString(), arguments.capture());

        Object[] values = arguments.getValue();
        assertInstanceOf(Timestamp.class, values[5]);
        assertInstanceOf(Timestamp.class, values[6]);
        assertEquals(capturedAt, ((Timestamp) values[5]).toInstant());
        assertEquals(expiresAt, ((Timestamp) values[6]).toInstant());
    }

    @Test
    void convertsCompletedAtToSqlTimestamp() {
        JdbcTemplate jdbcTemplate = mock(JdbcTemplate.class);
        RobotImageStore store = new RobotImageStore(jdbcTemplate);
        UUID imageId = UUID.randomUUID();
        Instant uploadedAt = Instant.parse("2026-07-31T00:01:00Z");

        store.markUploaded(imageId, 1024L, uploadedAt);

        ArgumentCaptor<Object[]> arguments =
                ArgumentCaptor.forClass(Object[].class);
        verify(jdbcTemplate).update(anyString(), arguments.capture());

        Object[] values = arguments.getValue();
        assertInstanceOf(Timestamp.class, values[1]);
        assertEquals(uploadedAt, ((Timestamp) values[1]).toInstant());
    }
}
