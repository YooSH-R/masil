package com.ssafy.backend.auth.sms;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

@Component
@Profile("local")
public class LocalSmsSender implements SmsSender {

    private static final Logger log = LoggerFactory.getLogger(LocalSmsSender.class);

    @Override
    public void sendVerificationCode(String phoneNumber, String code) {
        log.info("[LOCAL SMS] phoneNumber={}, verificationCode={}", phoneNumber, code);
    }
}
