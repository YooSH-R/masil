package com.ssafy.backend.walk.application;

import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.DateTimeException;
import java.util.Base64;

@Component
public class WalkCursorCodec {

    public String encode(Instant createdAt, Long walkId) {
        String value = createdAt.getEpochSecond()
                + ":" + createdAt.getNano()
                + ":" + walkId;
        return Base64.getUrlEncoder()
                .withoutPadding()
                .encodeToString(value.getBytes(StandardCharsets.UTF_8));
    }

    public Cursor decode(String value) {
        if (value == null || value.isBlank()) {
            return new Cursor(null, Long.MAX_VALUE);
        }
        try {
            String decoded = new String(
                    Base64.getUrlDecoder().decode(value),
                    StandardCharsets.UTF_8
            );
            String[] parts = decoded.split(":", -1);
            if (parts.length != 3) {
                throw new IllegalArgumentException("invalid cursor parts");
            }
            long seconds = Long.parseLong(parts[0]);
            int nanos = Integer.parseInt(parts[1]);
            long walkId = Long.parseLong(parts[2]);
            if (nanos < 0 || nanos > 999_999_999 || walkId <= 0) {
                throw new IllegalArgumentException("invalid cursor value");
            }
            return new Cursor(Instant.ofEpochSecond(seconds, nanos), walkId);
        } catch (IllegalArgumentException | DateTimeException exception) {
            throw new BusinessException(ErrorCode.INVALID_REQUEST);
        }
    }

    public record Cursor(Instant createdAt, Long walkId) {
    }
}
