package com.ssafy.backend.auth.sms;

public interface SmsSender {

    void sendVerificationCode(String phoneNumber, String code);
}
