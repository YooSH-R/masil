package com.ssafy.backend.walk.application;

import com.ssafy.backend.walk.infrastructure.persistence.WalkLocationStore;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.List;

@Component
public class WalkDistanceCalculator {

    private static final double EARTH_RADIUS_METERS = 6_371_008.8;

    public BigDecimal calculate(List<WalkLocationStore.Point> points) {
        double totalMeters = 0;
        for (int index = 1; index < points.size(); index++) {
            totalMeters += distance(points.get(index - 1), points.get(index));
        }
        return BigDecimal.valueOf(totalMeters).setScale(2, RoundingMode.HALF_UP);
    }

    private double distance(
            WalkLocationStore.Point from,
            WalkLocationStore.Point to
    ) {
        double fromLatitude = Math.toRadians(from.latitude().doubleValue());
        double toLatitude = Math.toRadians(to.latitude().doubleValue());
        double latitudeDelta = toLatitude - fromLatitude;
        double longitudeDelta = Math.toRadians(
                to.longitude().doubleValue() - from.longitude().doubleValue()
        );

        double haversine = Math.pow(Math.sin(latitudeDelta / 2), 2)
                + Math.cos(fromLatitude)
                * Math.cos(toLatitude)
                * Math.pow(Math.sin(longitudeDelta / 2), 2);
        double normalizedHaversine = Math.max(0, Math.min(1, haversine));
        return 2 * EARTH_RADIUS_METERS
                * Math.asin(Math.sqrt(normalizedHaversine));
    }
}
