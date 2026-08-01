package com.ssafy.backend.auth.controller;

import com.ssafy.backend.auth.dto.AuthResponse;
import com.ssafy.backend.auth.dto.LoginRequest;
import com.ssafy.backend.auth.dto.LogoutRequest;
import com.ssafy.backend.auth.dto.PasswordResetRequest;
import com.ssafy.backend.auth.dto.RefreshRequest;
import com.ssafy.backend.auth.dto.SignupRequest;
import com.ssafy.backend.auth.dto.VerificationConfirmRequest;
import com.ssafy.backend.auth.dto.VerificationConfirmResponse;
import com.ssafy.backend.auth.dto.VerificationSendRequest;
import com.ssafy.backend.auth.dto.VerificationSendResponse;
import com.ssafy.backend.auth.service.AuthService;
import com.ssafy.backend.auth.service.PasswordResetService;
import com.ssafy.backend.auth.service.VerificationService;
import com.ssafy.backend.common.ApiResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.PathVariable;

import java.util.UUID;

@RestController
@RequestMapping("/v1/auth")
public class AuthController {

    private final AuthService authService;
    private final VerificationService verificationService;
    private final PasswordResetService passwordResetService;

    public AuthController(
            AuthService authService,
            VerificationService verificationService,
            PasswordResetService passwordResetService
    ) {
        this.authService = authService;
        this.verificationService = verificationService;
        this.passwordResetService = passwordResetService;
    }

    @Operation(summary = "휴대전화 인증번호 발송")
    @PostMapping("/verifications")
    public ResponseEntity<ApiResponse<VerificationSendResponse>> sendVerification(
            @Valid @RequestBody VerificationSendRequest request
    ) {
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApiResponse.success(verificationService.send(request)));
    }

    @Operation(summary = "휴대전화 인증번호 확인")
    @PostMapping("/verifications/{verificationId}/confirm")
    public ApiResponse<VerificationConfirmResponse> confirmVerification(
            @PathVariable UUID verificationId,
            @Valid @RequestBody VerificationConfirmRequest request
    ) {
        return ApiResponse.success(
                verificationService.confirm(verificationId, request)
        );
    }

    @Operation(summary = "이메일 회원가입")
    @PostMapping("/signup")
    public ResponseEntity<ApiResponse<AuthResponse>> signup(
            @Valid @RequestBody SignupRequest request
    ) {
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApiResponse.success(authService.signup(request)));
    }

    @Operation(summary = "이메일 로그인")
    @PostMapping("/login")
    public ApiResponse<AuthResponse> login(
            @Valid @RequestBody LoginRequest request
    ) {
        return ApiResponse.success(authService.login(request));
    }

    @Operation(summary = "토큰 재발급")
    @PostMapping("/refresh")
    public ApiResponse<AuthResponse> refresh(
            @Valid @RequestBody RefreshRequest request
    ) {
        return ApiResponse.success(authService.refresh(request));
    }

    @Operation(
            summary = "로그아웃",
            security = @SecurityRequirement(name = "bearerAuth")
    )
    @PostMapping("/logout")
    public ResponseEntity<Void> logout(
            @AuthenticationPrincipal Long userId,
            @Valid @RequestBody LogoutRequest request
    ) {
        authService.logout(userId, request);
        return ResponseEntity.noContent().build();
    }

    @Operation(summary = "비밀번호 분실 시 재설정")
    @PostMapping("/password/reset")
    public ResponseEntity<Void> resetPassword(
            @Valid @RequestBody PasswordResetRequest request
    ) {
        passwordResetService.reset(request);
        return ResponseEntity.noContent().build();
    }
}
