package com.ssafy.backend.user.controller;

import com.ssafy.backend.common.ApiResponse;
import com.ssafy.backend.user.application.port.out.UserRepository;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Validated
@RequestMapping("/v1/users")
public class UserController {

    private final UserRepository userRepository;

    public UserController(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    @Operation(summary = "닉네임 사용 가능 여부")
    @GetMapping("/nickname-availability")
    public ApiResponse<NicknameAvailabilityResponse> nicknameAvailability(
            @RequestParam
            @NotBlank
            @Size(min = 2, max = 20)
            String nickname
    ) {
        return ApiResponse.success(
                new NicknameAvailabilityResponse(
                        nickname,
                        !userRepository.existsByNickname(nickname)
                )
        );
    }

    public record NicknameAvailabilityResponse(
            String nickname,
            boolean available
    ) {
    }
}
