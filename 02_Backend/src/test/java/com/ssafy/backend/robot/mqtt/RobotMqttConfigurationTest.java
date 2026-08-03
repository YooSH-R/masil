package com.ssafy.backend.robot.mqtt;

import org.junit.jupiter.api.Test;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageDeliveryException;
import org.springframework.messaging.MessageHandler;
import org.springframework.messaging.support.MessageBuilder;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

class RobotMqttConfigurationTest {

    private final RobotMqttConfiguration configuration =
            new RobotMqttConfiguration();

    @Test
    void connectsOutboundHandlerToOutboundChannel() {
        MessageHandler outboundHandler = mock(MessageHandler.class);
        Message<String> message = MessageBuilder.withPayload("{}").build();

        var channel = configuration.mqttOutboundChannel(outboundHandler);
        channel.send(message);

        verify(outboundHandler).handleMessage(message);
    }

    @Test
    void keepsInboundChannelAliveWhenResponsePublishingFails()
            throws Exception {
        RobotMqttMessageHandler inboundHandler =
                mock(RobotMqttMessageHandler.class);
        Message<String> message = MessageBuilder.withPayload("{}").build();
        doThrow(new MessageDeliveryException(
                message,
                "outbound unavailable"
        )).when(inboundHandler).handle(message);

        var channel = configuration.mqttInboundChannel(inboundHandler);

        assertDoesNotThrow(() -> channel.send(message));
    }

    @Test
    void keepsInboundChannelAliveWhenMessageProcessingFails()
            throws Exception {
        RobotMqttMessageHandler inboundHandler =
                mock(RobotMqttMessageHandler.class);
        Message<String> message = MessageBuilder.withPayload("{}").build();
        doThrow(new IllegalStateException(
                "database processing failed"
        )).when(inboundHandler).handle(message);

        var channel = configuration.mqttInboundChannel(inboundHandler);

        assertDoesNotThrow(() -> channel.send(message));
    }
}
