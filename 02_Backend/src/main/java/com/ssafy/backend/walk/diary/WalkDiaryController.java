package com.ssafy.backend.walk.diary;

import com.ssafy.backend.auth.security.UserPrincipal;
import com.ssafy.backend.common.api.ApiResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Pattern;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;

@Validated
@RestController
@RequestMapping("/v1")
@ConditionalOnProperty(name = "storage.s3.enabled", havingValue = "true")
public class WalkDiaryController {

    private final WalkDiaryService service;

    public WalkDiaryController(WalkDiaryService service) {
        this.service = service;
    }

    @Operation(summary = "산책일지 상세 조회")
    @SecurityRequirement(name = "bearerAuth")
    @GetMapping("/walk-diaries/{deviceId}/{walkDate}/{session}")
    public ApiResponse<WalkDiaryService.DiaryDetail> getDiary(
            @AuthenticationPrincipal UserPrincipal principal,
            @PathVariable
            @Pattern(regexp = "[A-Za-z0-9_-]{1,100}") String deviceId,
            @PathVariable
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE)
            LocalDate walkDate,
            @PathVariable @Min(1) @Max(6) int session
    ) {
        return ApiResponse.success(service.getDiary(
                principal.userId(),
                deviceId,
                walkDate,
                session
        ));
    }

    @Operation(summary = "산책일지 피드 조회")
    @SecurityRequirement(name = "bearerAuth")
    @GetMapping("/walk-diaries")
    public ApiResponse<WalkDiaryService.DiaryFeed> getFeed(
            @AuthenticationPrincipal UserPrincipal principal,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE)
            LocalDate beforeDate,
            @RequestParam(defaultValue = "30") @Min(1) @Max(100) int size
    ) {
        return ApiResponse.success(service.getFeed(
                principal.userId(),
                beforeDate,
                size
        ));
    }
}
