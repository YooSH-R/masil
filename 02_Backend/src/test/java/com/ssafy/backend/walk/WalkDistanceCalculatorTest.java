package com.ssafy.backend.walk;

import com.ssafy.backend.walk.application.WalkDistanceCalculator;
import com.ssafy.backend.walk.infrastructure.persistence.WalkLocationStore;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;

class WalkDistanceCalculatorTest {

    private final WalkDistanceCalculator calculator = new WalkDistanceCalculator();

    @Test
    void returnsZeroForLessThanTwoPoints() {
        assertEquals(new BigDecimal("0.00"), calculator.calculate(List.of()));
        assertEquals(
                new BigDecimal("0.00"),
                calculator.calculate(List.of(point("37.0000000", "127.0000000", 0)))
        );
    }

    @Test
    void calculatesHaversineDistanceInSequenceOrder() {
        BigDecimal distance = calculator.calculate(List.of(
                point("37.0000000", "127.0000000", 0),
                point("37.0010000", "127.0000000", 1)
        ));

        assertEquals(new BigDecimal("111.20"), distance);
    }

    @Test
    void calculatesFiniteDistanceForNearlyAntipodalPoints() {
        BigDecimal distance = calculator.calculate(List.of(
                point("-89.0002945", "-6.7936937", 0),
                point("89.0002951", "173.2063069", 1)
        ));

        assertEquals(new BigDecimal("20015114.44"), distance);
    }

    private WalkLocationStore.Point point(
            String latitude,
            String longitude,
            int sequence
    ) {
        return new WalkLocationStore.Point(
                new BigDecimal(latitude),
                new BigDecimal(longitude),
                BigDecimal.ONE,
                sequence,
                Instant.EPOCH.plusSeconds(sequence)
        );
    }
}
