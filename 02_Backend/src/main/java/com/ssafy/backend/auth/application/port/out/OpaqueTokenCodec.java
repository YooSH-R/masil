package com.ssafy.backend.auth.application.port.out;

public interface OpaqueTokenCodec {

    String generate();

    String hash(String rawToken);
}
