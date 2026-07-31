package com.ssafy.backend.user.dto;

import jakarta.validation.constraints.NotBlank;

public record WithdrawMemberRequest(
        String currentPassword,
        @NotBlank
        String confirmation
) {
}
