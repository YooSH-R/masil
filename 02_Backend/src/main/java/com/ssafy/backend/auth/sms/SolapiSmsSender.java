package com.ssafy.backend.auth.sms;

import com.solapi.sdk.NurigoApp;
import com.solapi.sdk.message.model.Message;
import com.solapi.sdk.message.service.DefaultMessageService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

@Component
@Profile("!local")
public class SolapiSmsSender implements SmsSender {

    private final DefaultMessageService messageService;
    private final String sender;

    public SolapiSmsSender(
            @Value("${solapi.api-key}") String apiKey,
            @Value("${solapi.secret-key}") String secretKey,
            @Value("${solapi.sender}") String sender
    ) {
        this.messageService = NurigoApp.INSTANCE.initialize(
                apiKey,
                secretKey,
                "https://api.solapi.com"
        );
        this.sender = sender;
    }

    @Override
    public void sendVerificationCode(String phoneNumber, String code) {
        Message message = new Message();
        message.setFrom(sender);
        message.setTo(phoneNumber);
        message.setText("[마이실] 인증번호는 [" + code + "]입니다.");
        try {
            messageService.send(message);
        } catch (Exception exception) {
            throw new IllegalStateException("Solapi SMS 발송에 실패했습니다.", exception);
        }
    }
}
