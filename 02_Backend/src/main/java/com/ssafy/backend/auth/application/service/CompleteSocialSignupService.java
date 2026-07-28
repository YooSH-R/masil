package com.ssafy.backend.auth.application.service;

import com.ssafy.backend.auth.application.port.out.AuthTokenIssuer;
import com.ssafy.backend.auth.application.port.out.OpaqueTokenCodec;
import com.ssafy.backend.auth.application.port.out.SignupTicketRepository;
import com.ssafy.backend.auth.application.port.out.SocialAccountRepository;
import com.ssafy.backend.auth.application.result.SocialAuthenticationResult;
import com.ssafy.backend.auth.domain.SignupTicket;
import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import com.ssafy.backend.user.application.port.out.UserRepository;
import com.ssafy.backend.user.domain.User;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Instant;

@Service
public class CompleteSocialSignupService {

    private final SignupTicketRepository signupTicketRepository;
    private final SocialAccountRepository socialAccountRepository;
    private final UserRepository userRepository;
    private final AuthTokenIssuer authTokenIssuer;
    private final OpaqueTokenCodec opaqueTokenCodec;
    private final Clock clock;

    public CompleteSocialSignupService(
            SignupTicketRepository signupTicketRepository,
            SocialAccountRepository socialAccountRepository,
            UserRepository userRepository,
            AuthTokenIssuer authTokenIssuer,
            OpaqueTokenCodec opaqueTokenCodec,
            Clock clock
    ) {
        this.signupTicketRepository = signupTicketRepository;
        this.socialAccountRepository = socialAccountRepository;
        this.userRepository = userRepository;
        this.authTokenIssuer = authTokenIssuer;
        this.opaqueTokenCodec = opaqueTokenCodec;
        this.clock = clock;
    }

    @Transactional
    public SocialAuthenticationResult.Authenticated complete(
            String signupToken,
            String nickname,
            String deviceId
    ) {
        Instant now = clock.instant();
        SignupTicket ticket = signupTicketRepository
                .findByTokenHash(opaqueTokenCodec.hash(signupToken))
                .orElseThrow(() -> new BusinessException(ErrorCode.INVALID_SIGNUP_TOKEN));

        ticket.validateUsableAt(now);
        validateDevice(ticket, deviceId);
        validateAccountNotLinked(ticket);
        validateNicknameAvailable(nickname);

        User user = userRepository.save(User.newSocialUser(ticket.principal().email(), nickname));
        socialAccountRepository.save(user.id(), ticket.principal());
        signupTicketRepository.markUsed(ticket.id(), now);

        return new SocialAuthenticationResult.Authenticated(
                authTokenIssuer.issue(user, deviceId),
                user
        );
    }

    private void validateDevice(SignupTicket ticket, String deviceId) {
        if (!ticket.deviceId().equals(deviceId)) {
            throw new BusinessException(ErrorCode.INVALID_SIGNUP_TOKEN);
        }
    }

    private void validateAccountNotLinked(SignupTicket ticket) {
        if (socialAccountRepository.exists(
                ticket.principal().provider(),
                ticket.principal().providerUserId()
        )) {
            throw new BusinessException(ErrorCode.SOCIAL_ACCOUNT_ALREADY_LINKED);
        }
    }

    private void validateNicknameAvailable(String nickname) {
        if (userRepository.existsByNickname(nickname)) {
            throw new BusinessException(ErrorCode.NICKNAME_DUPLICATED);
        }
    }
}
