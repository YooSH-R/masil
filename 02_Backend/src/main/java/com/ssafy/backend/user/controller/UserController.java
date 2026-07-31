package com.ssafy.backend.user.controller;

import com.ssafy.backend.common.ApiResponse;
import com.ssafy.backend.user.dto.ChangePasswordRequest;
import com.ssafy.backend.user.dto.MemberResponse;
import com.ssafy.backend.user.dto.UpdateMemberRequest;
import com.ssafy.backend.user.dto.WithdrawMemberRequest;
import com.ssafy.backend.user.service.MemberService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestAttribute;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/v1/users")
public class UserController {

    private final MemberService memberService;

    public UserController(MemberService memberService) {
        this.memberService = memberService;
    }

    @Operation(
            summary = "내 회원정보 조회",
            security = @SecurityRequirement(name = "bearerAuth")
    )
    @GetMapping("/me")
    public ApiResponse<MemberResponse> getMe(
            @AuthenticationPrincipal Long userId
    ) {
        return ApiResponse.success(memberService.getMember(userId));
    }

    @Operation(
            summary = "내 회원정보 수정",
            security = @SecurityRequirement(name = "bearerAuth")
    )
    @PatchMapping("/me")
    public ApiResponse<MemberResponse> updateMe(
            @AuthenticationPrincipal Long userId,
            @Valid @RequestBody UpdateMemberRequest request
    ) {
        return ApiResponse.success(
                memberService.updateMember(userId, request)
        );
    }

    @Operation(
            summary = "로그인 상태에서 비밀번호 변경",
            security = @SecurityRequirement(name = "bearerAuth")
    )
    @PatchMapping("/me/password")
    public ResponseEntity<Void> changePassword(
            @AuthenticationPrincipal Long userId,
            @RequestAttribute(
                    name = "authenticatedSessionId",
                    required = false
            )
            Long currentSessionId,
            @Valid @RequestBody ChangePasswordRequest request
    ) {
        memberService.changePassword(userId, currentSessionId, request);
        return ResponseEntity.noContent().build();
    }

    @Operation(
            summary = "회원탈퇴",
            security = @SecurityRequirement(name = "bearerAuth")
    )
    @DeleteMapping("/me")
    public ResponseEntity<Void> withdraw(
            @AuthenticationPrincipal Long userId,
            @Valid @RequestBody WithdrawMemberRequest request
    ) {
        memberService.withdraw(userId, request);
        return ResponseEntity.noContent().build();
    }
}
