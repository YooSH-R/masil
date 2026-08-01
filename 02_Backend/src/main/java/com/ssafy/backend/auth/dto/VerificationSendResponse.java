package com.ssafy.backend.auth.dto;

import java.time.Instant;
import java.util.UUID;

public record VerificationSendResponse(
        UUID verificationId,
        Instant expiresAt
) {
}
