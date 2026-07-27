package com.ssafy.backend.auth.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record RefreshRequest(
        @NotBlank String refreshToken,
        @NotBlank @Size(max = 255) String deviceId
) {
}
