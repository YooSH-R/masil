package com.ssafy.backend.robot.mqtt;

import org.eclipse.paho.client.mqttv3.MqttConnectOptions;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.integration.annotation.IntegrationComponentScan;
import org.springframework.integration.channel.DirectChannel;
import org.springframework.integration.core.MessageProducer;
import org.springframework.integration.mqtt.core.DefaultMqttPahoClientFactory;
import org.springframework.integration.mqtt.core.MqttPahoClientFactory;
import org.springframework.integration.mqtt.inbound.MqttPahoMessageDrivenChannelAdapter;
import org.springframework.integration.mqtt.outbound.MqttPahoMessageHandler;
import org.springframework.integration.mqtt.support.DefaultPahoMessageConverter;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.MessageHandler;

@Configuration
@IntegrationComponentScan
@EnableConfigurationProperties(MqttProperties.class)
@ConditionalOnProperty(name = "mqtt.enabled", havingValue = "true")
public class RobotMqttConfiguration {

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
    MessageChannel mqttInboundChannel() {
        return new DirectChannel();
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
    MessageChannel mqttOutboundChannel() {
        return new DirectChannel();
    }

    @Bean
    @org.springframework.integration.annotation.ServiceActivator(
            inputChannel = "mqttOutboundChannel"
    )
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
