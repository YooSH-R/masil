package com.ssafy.backend.auth.application.port.out;

import com.ssafy.backend.auth.domain.SignupTicket;
import com.ssafy.backend.auth.domain.SocialPrincipal;

import java.time.Instant;
import java.util.Optional;

public interface SignupTicketRepository {

    void save(String tokenHash, SocialPrincipal principal, String deviceId, Instant expiresAt);

    Optional<SignupTicket> findByTokenHash(String tokenHash);

    void markUsed(Long ticketId, Instant usedAt);
}
