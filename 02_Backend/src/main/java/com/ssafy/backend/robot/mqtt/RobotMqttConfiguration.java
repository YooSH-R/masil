package com.ssafy.backend.robot.mqtt;

import org.eclipse.paho.client.mqttv3.MqttConnectOptions;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.integration.channel.DirectChannel;
import org.springframework.integration.core.MessageProducer;
import org.springframework.integration.mqtt.core.DefaultMqttPahoClientFactory;
import org.springframework.integration.mqtt.core.MqttPahoClientFactory;
import org.springframework.integration.mqtt.inbound.MqttPahoMessageDrivenChannelAdapter;
import org.springframework.integration.mqtt.outbound.MqttPahoMessageHandler;
import org.springframework.integration.mqtt.support.DefaultPahoMessageConverter;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.MessageHandler;
import org.springframework.messaging.MessagingException;

@Configuration
@EnableConfigurationProperties(MqttProperties.class)
@ConditionalOnProperty(name = "mqtt.enabled", havingValue = "true")
public class RobotMqttConfiguration {

    private static final Logger log = LoggerFactory.getLogger(
            RobotMqttConfiguration.class
    );

    @Bean
    MqttPahoClientFactory mqttClientFactory(MqttProperties properties) {
        MqttConnectOptions options = new MqttConnectOptions();
        options.setServerURIs(new String[]{properties.url()});
        options.setAutomaticReconnect(true);
        options.setCleanSession(false);
        if (properties.username() != null && !properties.username().isBlank()) {
            options.setUserName(properties.username());
        }
        if (properties.password() != null && !properties.password().isBlank()) {
            options.setPassword(properties.password().toCharArray());
        }

        DefaultMqttPahoClientFactory factory = new DefaultMqttPahoClientFactory();
        factory.setConnectionOptions(options);
        return factory;
    }

    @Bean
    MessageChannel mqttInboundChannel(
            RobotMqttMessageHandler messageHandler
    ) {
        DirectChannel channel = new DirectChannel();
        channel.subscribe(message -> {
            try {
                @SuppressWarnings("unchecked")
                var stringMessage =
                        (org.springframework.messaging.Message<String>) message;
                messageHandler.handle(stringMessage);
            } catch (tools.jackson.core.JacksonException exception) {
                log.warn(
                        "잘못된 MQTT JSON 메시지를 폐기합니다. topic={}, reason={}",
                        message.getHeaders().get(
                                org.springframework.integration.mqtt.support
                                        .MqttHeaders.RECEIVED_TOPIC
                        ),
                        exception.getMessage()
                );
            } catch (IllegalArgumentException exception) {
                log.warn(
                        "유효하지 않은 MQTT 메시지를 폐기합니다. reason={}",
                        exception.getMessage()
                );
            } catch (MessagingException exception) {
                log.error(
                        "MQTT 수신 메시지 처리 중 응답 발행에 실패했습니다. "
                                + "inbound 연결은 유지합니다.",
                        exception
                );
            } catch (RuntimeException exception) {
                log.error(
                        "MQTT 수신 메시지 처리에 실패했습니다. "
                                + "재전송 루프 방지를 위해 메시지를 폐기하고 "
                                + "inbound 연결은 유지합니다.",
                        exception
                );
            }
        });
        return channel;
    }

    @Bean
    MessageProducer mqttInbound(
            MqttProperties properties,
            MqttPahoClientFactory clientFactory,
            MessageChannel mqttInboundChannel
    ) {
        var adapter = new MqttPahoMessageDrivenChannelAdapter(
                properties.clientId() + "-in",
                clientFactory,
                RobotMqttTopics.EVENTS,
                RobotMqttTopics.HEARTBEAT,
                RobotMqttTopics.REQUEST_RESULTS
        );
        adapter.setCompletionTimeout(properties.completionTimeoutMs());
        adapter.setConverter(new DefaultPahoMessageConverter());
        adapter.setQos(1);
        adapter.setOutputChannel(mqttInboundChannel);
        return adapter;
    }

    @Bean
    MessageChannel mqttOutboundChannel(
            @Qualifier("mqttOutbound") MessageHandler outboundHandler
    ) {
        DirectChannel channel = new DirectChannel();
        channel.subscribe(outboundHandler);
        return channel;
    }

    @Bean
    MessageHandler mqttOutbound(
            MqttProperties properties,
            MqttPahoClientFactory clientFactory
    ) {
        var handler = new MqttPahoMessageHandler(
                properties.clientId() + "-out",
                clientFactory
        );
        handler.setAsync(true);
        handler.setDefaultQos(1);
        return handler;
    }
}
