package com.ssafy.backend.robot.mqtt;

public final class RobotMqttTopics {

    public static final String EVENTS = "robot-pet/v1/devices/+/events";
    public static final String HEARTBEAT = "robot-pet/v1/devices/+/heartbeat";
    public static final String REQUEST_RESULTS = "robot-pet/v1/devices/+/request-results";

    private RobotMqttTopics() {
    }

    public static String affection(String deviceId) {
        return "robot-pet/v1/devices/" + deviceId + "/affection";
    }

    public static String requests(String deviceId) {
        return "robot-pet/v1/devices/" + deviceId + "/requests";
    }

    public static String deviceIdFrom(String topic) {
        String[] segments = topic.split("/");
        if (segments.length != 5 || !"devices".equals(segments[2])) {
            throw new IllegalArgumentException("지원하지 않는 MQTT 토픽입니다: " + topic);
        }
        return segments[3];
    }
}
