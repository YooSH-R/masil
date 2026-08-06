package com.ssafy.backend.common.error;

import com.ssafy.backend.common.ApiException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.ConstraintViolationException;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

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

}
