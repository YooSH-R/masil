package com.ssafy.backend.pet.presentation;

import com.ssafy.backend.auth.security.UserPrincipal;
import com.ssafy.backend.common.ApiResponse;
import com.ssafy.backend.pet.application.PetAffinitySnapshot;
import com.ssafy.backend.pet.application.PetService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import jakarta.validation.constraints.Positive;
import org.springframework.http.MediaType;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.time.Instant;

@Validated
@RestController
@RequestMapping("/v1/pets")
public class PetAffinityController {

    private final PetService petService;
    private final PetAffinitySseRegistry sseRegistry;

    public PetAffinityController(
            PetService petService,
            PetAffinitySseRegistry sseRegistry
    ) {
        this.petService = petService;
        this.sseRegistry = sseRegistry;
    }

    @Operation(summary = "반려동물 호감도 조회")
    @SecurityRequirement(name = "bearerAuth")
    @GetMapping("/{petId}/affinity")
    public ApiResponse<PetAffinityResponse> getAffinity(
            @AuthenticationPrincipal UserPrincipal principal,
            @PathVariable @Positive Long petId
    ) {
        return ApiResponse.success(PetAffinityResponse.from(
                petService.getAffinity(principal.userId(), petId)
        ));
    }

    @Operation(summary = "반려동물 호감도 실시간 구독")
    @SecurityRequirement(name = "bearerAuth")
    @GetMapping(
            value = "/{petId}/affinity/stream",
            produces = MediaType.TEXT_EVENT_STREAM_VALUE
    )
    public SseEmitter streamAffinity(
            @AuthenticationPrincipal UserPrincipal principal,
            @PathVariable @Positive Long petId
    ) {
        PetAffinitySnapshot snapshot = petService.getAffinity(
                principal.userId(),
                petId
        );
        return sseRegistry.subscribe(snapshot);
    }

    public record PetAffinityResponse(
            long petId,
            int score,
            int level,
            String mood,
            Instant updatedAt
    ) {
        static PetAffinityResponse from(PetAffinitySnapshot snapshot) {
            return new PetAffinityResponse(
                    snapshot.petId(),
                    snapshot.score(),
                    snapshot.level(),
                    snapshot.mood(),
                    snapshot.updatedAt()
            );
        }
    }
}
