package com.ssafy.backend.pet.infrastructure.persistence;

public interface PetRobotStatusProjection {

    Long getRobotId();

    Boolean getOnline();

    Integer getBatteryLevel();
}
