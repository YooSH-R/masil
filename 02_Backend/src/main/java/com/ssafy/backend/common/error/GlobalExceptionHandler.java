package com.ssafy.backend.common.error;

import com.ssafy.backend.common.ApiException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.ConstraintViolationException;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
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
        return ResponseEntity.status(exception.getStatus())
                .body(ErrorResponse.of(
                        exception.getCode(),
                        exception.getMessage(),
                        request
                ));
    }

    @ExceptionHandler(BusinessException.class)
    public ResponseEntity<ErrorResponse> handleBusinessException(
            BusinessException exception,
            HttpServletRequest request
    ) {
        ErrorCode errorCode = exception.errorCode();
        return ResponseEntity.status(errorCode.status())
                .body(ErrorResponse.of(errorCode, request));
    }

    @ExceptionHandler({
            MethodArgumentNotValidException.class,
            ConstraintViolationException.class,
            HttpMessageNotReadableException.class
    })
    public ResponseEntity<ErrorResponse> handleValidationException(
            Exception exception,
            HttpServletRequest request
    ) {
        return ResponseEntity.badRequest()
                .body(ErrorResponse.of(ErrorCode.INVALID_REQUEST, request));
    }

    public record ErrorResponse(
            boolean success,
            ErrorBody error,
            String traceId,
            Instant timestamp
    ) {
        private static ErrorResponse of(ErrorCode errorCode, HttpServletRequest request) {
            return of(errorCode.name(), errorCode.message(), request);
        }

        private static ErrorResponse of(
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
    }

    public record ErrorBody(String code, String message, Map<String, Object> details) {
    }
}
