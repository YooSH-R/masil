package com.ssafy.backend.auth.application.port.out;

import java.time.Instant;

public interface AuthSessionStore {

    void save(Long userId, String deviceId, String refreshTokenHash, Instant expiresAt);
}
