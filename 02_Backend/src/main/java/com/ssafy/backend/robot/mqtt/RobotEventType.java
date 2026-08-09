package com.ssafy.backend.robot.mqtt;

public enum RobotEventType {
    CALL_AND_RESPONSE(2),
    WALK_COMPLETED(10),
    CARE_ACTION(3),
    NEGATIVE_REACTION(-3),
    LONG_INACTIVITY(-1);

    private final int scoreChange;

    RobotEventType(int scoreChange) {
        this.scoreChange = scoreChange;
    }

    public int scoreChange() {
        return scoreChange;
    }
}
