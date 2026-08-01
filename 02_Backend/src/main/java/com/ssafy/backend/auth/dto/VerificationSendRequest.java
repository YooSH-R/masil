package com.ssafy.backend.auth.dto;

import com.ssafy.backend.auth.domain.VerificationPurpose;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

public record VerificationSendRequest(
        @NotBlank
        @Pattern(
                regexp = "^01[016789][0-9]{7,8}$",
                message = "휴대전화 번호는 하이픈 없이 입력해야 합니다."
        )
        String phoneNumber,
        VerificationPurpose purpose
) {
}
