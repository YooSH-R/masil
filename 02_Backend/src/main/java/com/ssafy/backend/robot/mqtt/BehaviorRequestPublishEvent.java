package com.ssafy.backend.robot.mqtt;

import java.time.Instant;

record BehaviorRequestPublishEvent(
        BehaviorRequestMessage request,
        Instant publishedAt
) {
}
