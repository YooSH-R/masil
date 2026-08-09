package com.ssafy.backend.robot.presentation;

import com.ssafy.backend.auth.security.UserPrincipal;
import com.ssafy.backend.common.ApiResponse;
import com.ssafy.backend.robot.application.RobotPairingRateLimiter;
import com.ssafy.backend.robot.application.RobotPairingResult;
import com.ssafy.backend.robot.application.RobotPairingService;
import com.ssafy.backend.robot.application.RobotRegistrationPreview;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;

@RestController
@RequestMapping("/v1/robots")
public class RobotPairingController {

    private final RobotPairingService pairingService;
    private final RobotPairingRateLimiter rateLimiter;

    public RobotPairingController(
            RobotPairingService pairingService,
            RobotPairingRateLimiter rateLimiter
    ) {
        this.pairingService = pairingService;
        this.rateLimiter = rateLimiter;
    }

    @Operation(summary = "정적 QR을 이용한 로봇 등록")
    @SecurityRequirement(name = "bearerAuth")
    @PostMapping("/pairings")
    public ResponseEntity<ApiResponse<RobotPairingResponse>> pair(
            @AuthenticationPrincipal UserPrincipal principal,
            @Valid @RequestBody RobotPairingRequest request
    ) {
        Long userId = principal.userId();
        rateLimiter.checkAllowed(userId);
        RobotPairingResult result = pairingService.pair(
                userId,
                request.petId(),
                request.qrToken()
        );
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApiResponse.success(RobotPairingResponse.from(result)));
    }

    @Operation(summary = "QR 기기 등록 가능 여부 확인")
    @SecurityRequirement(name = "bearerAuth")
    @PostMapping("/registrations/validate")
    public ResponseEntity<ApiResponse<RobotRegistrationPreviewResponse>> validateRegistration(
            @AuthenticationPrincipal UserPrincipal principal,
            @Valid @RequestBody RobotRegistrationValidationRequest request
    ) {
        Long userId = principal.userId();
        rateLimiter.checkAllowed(userId);
        RobotRegistrationPreview preview = pairingService.validateRegistration(
                userId,
                request.qrToken()
        );
        return ResponseEntity.ok(
                ApiResponse.success(RobotRegistrationPreviewResponse.from(preview))
        );
    }

    @Operation(summary = "QR 검증 후 새 펫 생성 및 기기 등록")
    @SecurityRequirement(name = "bearerAuth")
    @PostMapping("/registrations")
    public ResponseEntity<ApiResponse<RobotPairingResponse>> registerNewPet(
            @AuthenticationPrincipal UserPrincipal principal,
            @Valid @RequestBody RobotRegistrationRequest request
    ) {
        Long userId = principal.userId();
        rateLimiter.checkAllowed(userId);
        RobotPairingResult result = pairingService.registerNewPet(
                userId,
                request.petName(),
                request.qrToken()
        );
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApiResponse.success(RobotPairingResponse.from(result)));
    }

    public record RobotPairingRequest(
            @NotNull @Positive Long petId,
            @NotBlank
            @Size(min = 43, max = 512)
            @Pattern(regexp = "^[A-Za-z0-9_-]+$")
            String qrToken
    ) {
    }

    public record RobotRegistrationValidationRequest(
            @NotBlank
            @Size(min = 43, max = 512)
            @Pattern(regexp = "^[A-Za-z0-9_-]+$")
            String qrToken
    ) {
    }

    public record RobotRegistrationRequest(
            @NotBlank @Size(max = 100) String petName,
            @NotBlank
            @Size(min = 43, max = 512)
            @Pattern(regexp = "^[A-Za-z0-9_-]+$")
            String qrToken
    ) {
    }

    public record RobotRegistrationPreviewResponse(
            String serialNumber,
            String modelName,
            String firmwareVersion,
            String registrationStatus
    ) {
        static RobotRegistrationPreviewResponse from(RobotRegistrationPreview preview) {
            return new RobotRegistrationPreviewResponse(
                    preview.serialNumber(),
                    preview.modelName(),
                    preview.firmwareVersion(),
                    "AVAILABLE"
            );
        }
    }

    public record RobotPairingResponse(
            Long pairingId,
            Long robotId,
            Long petId,
            String serialNumber,
            String modelName,
            String firmwareVersion,
            String pairingStatus,
            Instant pairedAt
    ) {
        static RobotPairingResponse from(RobotPairingResult result) {
            return new RobotPairingResponse(
                    result.pairingId(),
                    result.robotId(),
                    result.petId(),
                    result.serialNumber(),
                    result.modelName(),
                    result.firmwareVersion(),
                    "PAIRED",
                    result.pairedAt()
            );
        }
    }
}
