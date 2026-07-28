package com.ssafy.backend.auth.presentation;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.ssafy.backend.auth.application.result.SocialAuthenticationResult;
import com.ssafy.backend.auth.application.service.CompleteSocialSignupService;
import com.ssafy.backend.auth.application.service.GoogleAuthenticationService;
import com.ssafy.backend.auth.application.service.KakaoAuthenticationService;
import com.ssafy.backend.common.api.ApiResponse;
import com.ssafy.backend.user.application.port.out.UserRepository;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;

@Validated
@RestController
@RequestMapping("/v1")
public class SocialAuthenticationController {

    private static final String NICKNAME_PATTERN = "^[가-힣a-zA-Z0-9_-]{2,20}$";

    private final GoogleAuthenticationService googleAuthenticationService;
    private final KakaoAuthenticationService kakaoAuthenticationService;
    private final CompleteSocialSignupService completeSocialSignupService;
    private final UserRepository userRepository;

    public SocialAuthenticationController(
            GoogleAuthenticationService googleAuthenticationService,
            KakaoAuthenticationService kakaoAuthenticationService,
            CompleteSocialSignupService completeSocialSignupService,
            UserRepository userRepository
    ) {
        this.googleAuthenticationService = googleAuthenticationService;
        this.kakaoAuthenticationService = kakaoAuthenticationService;
        this.completeSocialSignupService = completeSocialSignupService;
        this.userRepository = userRepository;
    }

    @PostMapping("/auth/oauth/google")
    public ApiResponse<SocialAuthenticationResponse> authenticateGoogle(
            @Valid @RequestBody GoogleAuthenticationRequest request
    ) {
        SocialAuthenticationResult result = googleAuthenticationService.authenticate(
                request.idToken(),
                request.deviceId()
        );
        return ApiResponse.success(SocialAuthenticationResponse.from(result));
    }

    @PostMapping("/auth/oauth/kakao")
    public ApiResponse<SocialAuthenticationResponse> authenticateKakao(
            @Valid @RequestBody KakaoAuthenticationRequest request
    ) {
        SocialAuthenticationResult result = kakaoAuthenticationService.authenticate(
                request.idToken(),
                request.deviceId()
        );
        return ApiResponse.success(SocialAuthenticationResponse.from(result));
    }

    @PostMapping("/auth/oauth/signup")
    public ResponseEntity<ApiResponse<AuthenticationResponse>> completeSignup(
            @Valid @RequestBody CompleteSocialSignupRequest request
    ) {
        SocialAuthenticationResult.Authenticated result = completeSocialSignupService.complete(
                request.signupToken(),
                request.nickname(),
                request.deviceId()
        );
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApiResponse.success(AuthenticationResponse.from(result)));
    }

    @GetMapping("/users/nickname-availability")
    public ApiResponse<NicknameAvailabilityResponse> checkNickname(
            @RequestParam
            @Pattern(regexp = NICKNAME_PATTERN)
            String nickname
    ) {
        return ApiResponse.success(new NicknameAvailabilityResponse(
                nickname,
                !userRepository.existsByNickname(nickname)
        ));
    }

    public record GoogleAuthenticationRequest(
            @NotBlank String idToken,
            @NotBlank @Size(max = 255) String deviceId
    ) {
    }

    public record KakaoAuthenticationRequest(
            @NotBlank String idToken,
            @NotBlank @Size(max = 255) String deviceId
    ) {
    }

    public record CompleteSocialSignupRequest(
            @NotBlank String signupToken,
            @NotBlank @Pattern(regexp = NICKNAME_PATTERN) String nickname,
            @NotBlank @Size(max = 255) String deviceId
    ) {
    }

    @JsonInclude(JsonInclude.Include.NON_NULL)
    public record SocialAuthenticationResponse(
            String status,
            String accessToken,
            String refreshToken,
            Instant accessTokenExpiresAt,
            Instant refreshTokenExpiresAt,
            UserResponse user,
            String signupToken,
            Instant signupTokenExpiresAt,
            ProfileResponse profile
    ) {
        static SocialAuthenticationResponse from(SocialAuthenticationResult result) {
            if (result instanceof SocialAuthenticationResult.Authenticated authenticated) {
                return new SocialAuthenticationResponse(
                        "AUTHENTICATED",
                        authenticated.tokens().accessToken(),
                        authenticated.tokens().refreshToken(),
                        authenticated.tokens().accessTokenExpiresAt(),
                        authenticated.tokens().refreshTokenExpiresAt(),
                        UserResponse.from(authenticated),
                        null,
                        null,
                        null
                );
            }

            SocialAuthenticationResult.SignupRequired signupRequired =
                    (SocialAuthenticationResult.SignupRequired) result;
            return new SocialAuthenticationResponse(
                    "SIGNUP_REQUIRED",
                    null,
                    null,
                    null,
                    null,
                    null,
                    signupRequired.signupToken(),
                    signupRequired.signupTokenExpiresAt(),
                    new ProfileResponse(
                            signupRequired.provider().name(),
                            signupRequired.email(),
                            signupRequired.suggestedNickname()
                    )
            );
        }
    }

    public record AuthenticationResponse(
            String accessToken,
            String refreshToken,
            Instant accessTokenExpiresAt,
            Instant refreshTokenExpiresAt,
            UserResponse user
    ) {
        static AuthenticationResponse from(
                SocialAuthenticationResult.Authenticated authenticated
        ) {
            return new AuthenticationResponse(
                    authenticated.tokens().accessToken(),
                    authenticated.tokens().refreshToken(),
                    authenticated.tokens().accessTokenExpiresAt(),
                    authenticated.tokens().refreshTokenExpiresAt(),
                    UserResponse.from(authenticated)
            );
        }
    }

    public record UserResponse(Long userId, String nickname) {
        static UserResponse from(SocialAuthenticationResult.Authenticated authenticated) {
            return new UserResponse(
                    authenticated.user().id(),
                    authenticated.user().nickname()
            );
        }
    }

    public record ProfileResponse(
            String provider,
            String email,
            String suggestedNickname
    ) {
    }

    public record NicknameAvailabilityResponse(String nickname, boolean available) {
    }
}
