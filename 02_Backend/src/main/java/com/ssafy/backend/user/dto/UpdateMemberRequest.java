package com.ssafy.backend.user.dto;

import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record UpdateMemberRequest(
        @Size(min = 2, max = 20)
        String nickname,
        @Pattern(
                regexp = "^01[016789][0-9]{7,8}$",
                message = "휴대전화 번호는 하이픈 없이 입력해야 합니다."
        )
        String phoneNumber,
        @Size(min = 1, max = 512)
        String verificationToken
) {
}
