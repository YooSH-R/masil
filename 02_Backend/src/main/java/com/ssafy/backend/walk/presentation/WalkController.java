package com.ssafy.backend.walk.presentation;

import com.ssafy.backend.auth.security.UserPrincipal;
import com.ssafy.backend.common.ApiResponse;
import com.ssafy.backend.robot.security.DevicePrincipal;
import com.ssafy.backend.walk.application.WalkCommandService;
import com.ssafy.backend.walk.application.WalkCompletionService;
import com.ssafy.backend.walk.application.WalkLocationBatchResult;
import com.ssafy.backend.walk.application.WalkPageResult;
import com.ssafy.backend.walk.application.WalkProposalResult;
import com.ssafy.backend.walk.application.WalkProposalService;
import com.ssafy.backend.walk.application.WalkQueryService;
import com.ssafy.backend.walk.application.WalkResult;
import com.ssafy.backend.walk.application.WalkSummaryResult;
import com.ssafy.backend.walk.domain.WalkProposalStatus;
import com.ssafy.backend.walk.infrastructure.persistence.WalkLocationStore;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;

@Validated
@RestController
@RequestMapping("/v1")
public class WalkController {

    private final WalkCommandService commandService;
    private final WalkCompletionService completionService;
    private final WalkProposalService proposalService;
    private final WalkQueryService queryService;

    public WalkController(
            WalkCommandService commandService,
            WalkCompletionService completionService,
            WalkProposalService proposalService,
            WalkQueryService queryService
    ) {
        this.commandService = commandService;
        this.completionService = completionService;
        this.proposalService = proposalService;
        this.queryService = queryService;
    }

    @Operation(summary = "현재 산책 제안 조회")
    @SecurityRequirement(name = "bearerAuth")
    @GetMapping("/walk-proposals/current")
    public ResponseEntity<ApiResponse<CurrentProposalResponse>> getCurrentProposal(
            @AuthenticationPrincipal UserPrincipal principal
    ) {
        return queryService.getCurrentProposal(principal.userId())
                .map(result -> ResponseEntity.ok(ApiResponse.success(
                        CurrentProposalResponse.from(result)
                )))
                .orElseGet(() -> ResponseEntity.noContent().build());
    }

    @Operation(summary = "산책 제안 수락 또는 거절")
    @SecurityRequirement(name = "bearerAuth")
    @PostMapping("/walk-proposals/{proposalId}/responses")
    public ResponseEntity<Void> respondToProposal(
            @AuthenticationPrincipal UserPrincipal principal,
            @PathVariable @Positive Long proposalId,
            @Valid @RequestBody ProposalResponseRequest request
    ) {
        proposalService.respond(
                principal.userId(),
                proposalId,
                request.response().toStatus(),
                request.respondedAt()
        );
        return ResponseEntity.noContent().build();
    }

    @Operation(summary = "산책 세션 생성")
    @SecurityRequirement(name = "bearerAuth")
    @PostMapping("/walks")
    public ResponseEntity<ApiResponse<WalkResult>> createWalk(
            @AuthenticationPrincipal UserPrincipal principal,
            @Valid @RequestBody CreateWalkRequest request
    ) {
        WalkCommandService.CreationResult result = commandService.createWalk(
                principal.userId(),
                request.proposalId(),
                request.petId(),
                request.robotId()
        );
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApiResponse.success(result.walk()));
    }

    @Operation(summary = "디바이스의 산책 시작 보고")
    @SecurityRequirement(name = "deviceAuth")
    @PostMapping("/walks/{walkId}/start")
    public ApiResponse<WalkResult> startWalk(
            @AuthenticationPrincipal DevicePrincipal principal,
            @PathVariable @Positive Long walkId,
            @Valid @RequestBody StartWalkRequest request
    ) {
        return ApiResponse.success(commandService.startWalk(
                principal.robotId(),
                walkId,
                request.startedAt()
        ));
    }

    @Operation(summary = "산책 GPS 좌표 일괄 저장")
    @SecurityRequirement(name = "bearerAuth")
    @PostMapping("/walks/{walkId}/locations/batch")
    public ApiResponse<WalkLocationBatchResult> saveLocations(
            @AuthenticationPrincipal UserPrincipal principal,
            @PathVariable @Positive Long walkId,
            @RequestHeader(value = "X-Idempotency-Key", required = false)
            @Size(min = 1, max = 100)
            @Pattern(regexp = "^[A-Za-z0-9._:-]+$")
            String idempotencyKey,
            @Valid @RequestBody WalkLocationBatchRequest request
    ) {
        List<WalkLocationStore.Point> points = request.points().stream()
                .map(WalkLocationPointRequest::toPoint)
                .toList();
        return ApiResponse.success(commandService.saveLocations(
                principal.userId(),
                walkId,
                idempotencyKey,
                points
        ));
    }

    @Operation(summary = "디바이스의 산책 종료 보고")
    @SecurityRequirement(name = "deviceAuth")
    @PostMapping("/walks/{walkId}/end")
    public ApiResponse<WalkResult> endWalk(
            @AuthenticationPrincipal DevicePrincipal principal,
            @PathVariable @Positive Long walkId,
            @Valid @RequestBody EndWalkRequest request
    ) {
        return ApiResponse.success(completionService.endWalk(
                principal.robotId(),
                principal.deviceId(),
                walkId,
                request.endedAt()
        ));
    }

    @Operation(summary = "산책 상세 조회")
    @SecurityRequirement(name = "bearerAuth")
    @GetMapping("/walks/{walkId}")
    public ApiResponse<WalkResult> getWalk(
            @AuthenticationPrincipal UserPrincipal principal,
            @PathVariable @Positive Long walkId
    ) {
        return ApiResponse.success(queryService.getWalk(
                principal.userId(),
                walkId
        ));
    }

    @Operation(summary = "산책 목록 조회")
    @SecurityRequirement(name = "bearerAuth")
    @GetMapping("/walks")
    public ApiResponse<WalkPageResult> getWalks(
            @AuthenticationPrincipal UserPrincipal principal,
            @RequestParam(required = false)
            @Size(max = 256)
            String cursor,
            @RequestParam(defaultValue = "20")
            @Min(1) @Max(100)
            int limit
    ) {
        return ApiResponse.success(queryService.getWalks(
                principal.userId(),
                cursor,
                limit
        ));
    }

    @Operation(summary = "산책 거리·시간·경로 조회")
    @SecurityRequirement(name = "bearerAuth")
    @GetMapping("/walks/{walkId}/summary")
    public ApiResponse<WalkSummaryResult> getSummary(
            @AuthenticationPrincipal UserPrincipal principal,
            @PathVariable @Positive Long walkId
    ) {
        return ApiResponse.success(queryService.getSummary(
                principal.userId(),
                walkId
        ));
    }

    public record CurrentProposalResponse(
            Long proposalId,
            Long petId,
            Long robotId,
            String message,
            String reason,
            Instant expiresAt
    ) {
        static CurrentProposalResponse from(WalkProposalResult result) {
            return new CurrentProposalResponse(
                    result.proposalId(),
                    result.petId(),
                    result.robotId(),
                    result.message(),
                    result.reason(),
                    result.expiresAt()
            );
        }
    }

    public record ProposalResponseRequest(
            @NotNull ProposalDecision response,
            @NotNull Instant respondedAt
    ) {
    }

    public enum ProposalDecision {
        ACCEPTED,
        DECLINED;

        WalkProposalStatus toStatus() {
            return WalkProposalStatus.valueOf(name());
        }
    }

    public record CreateWalkRequest(
            @NotNull @Positive Long proposalId,
            @NotNull @Positive Long petId,
            @NotNull @Positive Long robotId
    ) {
    }

    public record StartWalkRequest(@NotNull Instant startedAt) {
    }

    public record EndWalkRequest(@NotNull Instant endedAt) {
    }

    public record WalkLocationBatchRequest(
            @NotEmpty @Size(max = 100)
            List<@Valid WalkLocationPointRequest> points
    ) {
    }

    public record WalkLocationPointRequest(
            @NotNull @DecimalMin("-90.0") @DecimalMax("90.0")
            BigDecimal latitude,
            @NotNull @DecimalMin("-180.0") @DecimalMax("180.0")
            BigDecimal longitude,
            @DecimalMin("0.0") BigDecimal accuracy,
            @NotNull @PositiveOrZero Integer sequence,
            @NotNull Instant recordedAt
    ) {
        WalkLocationStore.Point toPoint() {
            return new WalkLocationStore.Point(
                    latitude,
                    longitude,
                    accuracy,
                    sequence,
                    recordedAt
            );
        }
    }
}
