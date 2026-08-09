package com.ssafy.backend.walk.application;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Configuration;

@Configuration
@EnableConfigurationProperties(WalkProposalProducerProperties.class)
public class WalkSchedulingConfiguration {
}
