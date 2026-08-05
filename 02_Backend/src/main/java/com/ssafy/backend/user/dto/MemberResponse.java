package com.ssafy.backend.user.dto;

import java.time.Instant;
import java.util.List;

public record MemberResponse(
        Long memberId,
        String email,
        String nickname,
        String phoneNumber,
        boolean phoneVerified,
        List<String> loginProviders,
        Instant createdAt
) {
}
