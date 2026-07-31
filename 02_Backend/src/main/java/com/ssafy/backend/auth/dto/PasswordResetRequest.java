package com.ssafy.backend.auth.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record PasswordResetRequest(
        @NotBlank
        @Pattern(
                regexp = "^01[016789][0-9]{7,8}$",
                message = "휴대전화 번호는 하이픈 없이 입력해야 합니다."
        )
        String phoneNumber,
        @NotBlank
        @Size(max = 512)
        String verificationToken,
        @NotBlank
        @Size(min = 8, max = 72)
        @Pattern(
                regexp = "^(?=.*[A-Za-z])(?=.*\\d).+$",
                message = "영문과 숫자를 포함해야 합니다."
        )
        String newPassword
) {
}
