package com.ssafy.backend.robot.mqtt;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class RobotMqttTopicsTest {

    @Test
    void extractsDeviceIdFromTopic() {
        assertEquals(
                "device-001",
                RobotMqttTopics.deviceIdFrom(
                        "robot-pet/v1/devices/device-001/events"
                )
        );
    }

    @Test
    void rejectsInvalidTopic() {
        assertThrows(
                IllegalArgumentException.class,
                () -> RobotMqttTopics.deviceIdFrom("invalid/topic")
        );
    }
}
