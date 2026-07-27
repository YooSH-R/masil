package com.ssafy.backend.common;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(ApiException.class)
    public ResponseEntity<ErrorResponse> handleApiException(
            ApiException exception,
            HttpServletRequest request
    ) {
        return ResponseEntity.status(exception.getStatus()).body(
                ErrorResponse.of(exception.getCode(), exception.getMessage(), null)
        );
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorResponse> handleValidation(
            MethodArgumentNotValidException exception
    ) {
        FieldError fieldError = exception.getBindingResult().getFieldErrors().stream()
                .findFirst()
                .orElse(null);

        Map<String, String> details = fieldError == null
                ? null
                : Map.of(
                        "field", fieldError.getField(),
                        "reason", fieldError.getDefaultMessage()
                );

        return ResponseEntity.badRequest().body(
                ErrorResponse.of(
                        "INVALID_REQUEST",
                        "요청값이 올바르지 않습니다.",
                        details
                )
        );
    }

    public record ErrorResponse(
            boolean success,
            ErrorBody error,
            String traceId,
            Instant timestamp
    ) {
        static ErrorResponse of(
                String code,
                String message,
                Map<String, String> details
        ) {
            return new ErrorResponse(
                    false,
                    new ErrorBody(code, message, details),
                    UUID.randomUUID().toString(),
                    Instant.now()
            );
        }
    }

    public record ErrorBody(
            String code,
            String message,
            Map<String, String> details
    ) {
    }
}
