package com.ssafy.backend.pet.presentation;

import com.ssafy.backend.auth.security.UserPrincipal;
import com.ssafy.backend.common.ApiResponse;
import com.ssafy.backend.pet.application.PetAffinityResult;
import com.ssafy.backend.pet.application.PetCreatedResult;
import com.ssafy.backend.pet.application.PetProfileResult;
import com.ssafy.backend.pet.application.PetRobotResult;
import com.ssafy.backend.pet.application.PetService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Null;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;

@Validated
@RestController
@RequestMapping("/v1/pets")
public class PetController {

    private final PetService petService;

    public PetController(PetService petService) {
        this.petService = petService;
    }

    @Operation(summary = "펫 생성")
    @SecurityRequirement(name = "bearerAuth")
    @PostMapping
    public ResponseEntity<ApiResponse<PetCreatedResponse>> create(
            @AuthenticationPrincipal UserPrincipal principal,
            @Parameter(
                    description = "요청마다 새로 생성하는 멱등성 키. "
                            + "같은 생성 요청 재시도에만 재사용하며 "
                            + "다른 요청에는 재사용하지 않습니다."
            )
            @RequestHeader("X-Idempotency-Key")
            @NotBlank
            @Size(max = 100)
            @Pattern(regexp = "^[A-Za-z0-9._:-]+$")
            String idempotencyKey,
            @Valid @RequestBody CreatePetRequest request
    ) {
        PetCreatedResult result = petService.create(
                principal.userId(),
                idempotencyKey,
                request.name()
        );
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApiResponse.success(PetCreatedResponse.from(result)));
    }

    @Operation(summary = "펫 프로필 조회")
    @SecurityRequirement(name = "bearerAuth")
    @GetMapping("/{petId}")
    public ApiResponse<PetProfileResponse> getProfile(
            @AuthenticationPrincipal UserPrincipal principal,
            @PathVariable @Positive Long petId
    ) {
        return ApiResponse.success(PetProfileResponse.from(
                petService.getProfile(principal.userId(), petId)
        ));
    }

    @Operation(summary = "펫 정보 수정")
    @SecurityRequirement(name = "bearerAuth")
    @PatchMapping("/{petId}")
    public ApiResponse<PetProfileResponse> update(
            @AuthenticationPrincipal UserPrincipal principal,
            @PathVariable @Positive Long petId,
            @Valid @RequestBody UpdatePetRequest request
    ) {
        return ApiResponse.success(PetProfileResponse.from(
                petService.update(principal.userId(), petId, request.name())
        ));
    }

    public record CreatePetRequest(
            @NotBlank @Size(max = 100) String name,
            @Null(message = "프로필 이미지 업로드는 현재 지원하지 않습니다.")
            String profileImage
    ) {
    }

    public record UpdatePetRequest(
            @NotBlank @Size(max = 100) String name,
            @Null(message = "프로필 이미지 업로드는 현재 지원하지 않습니다.")
            String profileImage
    ) {
    }

    public record PetCreatedResponse(
            Long petId,
            String name,
            AffinityResponse affinity,
            Instant createdAt
    ) {
        static PetCreatedResponse from(PetCreatedResult result) {
            return new PetCreatedResponse(
                    result.petId(),
                    result.name(),
                    AffinityResponse.from(result.affinity()),
                    result.createdAt()
            );
        }
    }

    public record PetProfileResponse(
            Long petId,
            String name,
            String profileImageUrl,
            AffinityResponse affinity,
            RobotResponse robot
    ) {
        static PetProfileResponse from(PetProfileResult result) {
            return new PetProfileResponse(
                    result.petId(),
                    result.name(),
                    result.profileImageUrl(),
                    AffinityResponse.from(result.affinity()),
                    RobotResponse.from(result.robot())
            );
        }
    }

    public record AffinityResponse(
            int score,
            int level,
            String mood
    ) {
        static AffinityResponse from(PetAffinityResult result) {
            return new AffinityResponse(
                    result.score(),
                    result.level(),
                    result.mood()
            );
        }
    }

    public record RobotResponse(
            Long robotId,
            boolean online,
            int batteryLevel
    ) {
        static RobotResponse from(PetRobotResult result) {
            if (result == null) {
                return null;
            }
            return new RobotResponse(
                    result.robotId(),
                    result.online(),
                    result.batteryLevel()
            );
        }
    }
}
