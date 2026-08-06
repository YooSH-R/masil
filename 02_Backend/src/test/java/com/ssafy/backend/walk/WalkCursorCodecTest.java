package com.ssafy.backend.walk;

import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import com.ssafy.backend.walk.application.WalkCursorCodec;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Base64;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class WalkCursorCodecTest {

    private final WalkCursorCodec codec = new WalkCursorCodec();

    @Test
    void roundTripsOpaqueCursor() {
        Instant createdAt = Instant.parse("2026-08-01T10:00:00.123456Z");

        WalkCursorCodec.Cursor cursor = codec.decode(codec.encode(createdAt, 123L));

        assertEquals(createdAt, cursor.createdAt());
        assertEquals(123L, cursor.walkId());
    }

    @Test
    void rejectsMalformedAndOutOfRangeCursor() {
        assertInvalid("not-base64!");
        String outOfRange = Base64.getUrlEncoder()
                .withoutPadding()
                .encodeToString(
                        "999999999999999999:0:1".getBytes(StandardCharsets.UTF_8)
                );
        assertInvalid(outOfRange);
    }

    private void assertInvalid(String cursor) {
        BusinessException exception = assertThrows(
                BusinessException.class,
                () -> codec.decode(cursor)
        );
        assertEquals(ErrorCode.INVALID_REQUEST, exception.errorCode());
    }
}
