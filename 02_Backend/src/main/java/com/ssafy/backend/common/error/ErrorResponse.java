package com.ssafy.backend.common.error;

import jakarta.servlet.http.HttpServletRequest;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

public record ErrorResponse(
        boolean success,
        ErrorBody error,
        String traceId,
        Instant timestamp
) {
    public static ErrorResponse of(
            ErrorCode errorCode,
            HttpServletRequest request
    ) {
        return of(errorCode.name(), errorCode.message(), request);
    }

    public static ErrorResponse of(
            String code,
            String message,
            HttpServletRequest request
    ) {
        Object existingTraceId = request.getAttribute("traceId");
        String traceId = existingTraceId == null
                ? UUID.randomUUID().toString()
                : existingTraceId.toString();
        return new ErrorResponse(
                false,
                new ErrorBody(code, message, Map.of()),
                traceId,
                Instant.now()
        );
    }

    public record ErrorBody(String code, String message, Map<String, Object> details) {
    }
}
