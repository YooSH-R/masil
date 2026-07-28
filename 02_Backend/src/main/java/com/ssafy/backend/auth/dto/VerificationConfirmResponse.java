package com.ssafy.backend.auth.dto;

import java.time.Instant;

public record VerificationConfirmResponse(
        String verificationToken,
        Instant expiresAt
) {
}
