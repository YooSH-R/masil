package com.ssafy.backend.robot.mqtt;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "mqtt")
public record MqttProperties(
        boolean enabled,
        String url,
        String clientId,
        String username,
        String password,
        long completionTimeoutMs
) {
}
