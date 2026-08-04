package com.ssafy.backend.walk.application;

import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import com.ssafy.backend.walk.infrastructure.persistence.SpringDataWalkRepository;
import com.ssafy.backend.walk.infrastructure.persistence.WalkJpaEntity;
import com.ssafy.backend.walk.infrastructure.persistence.WalkLocationStore;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;

@Service
public class WalkSummaryReadService {

    private final SpringDataWalkRepository walkRepository;
    private final WalkLocationStore locationStore;

    public WalkSummaryReadService(
            SpringDataWalkRepository walkRepository,
            WalkLocationStore locationStore
    ) {
        this.walkRepository = walkRepository;
        this.locationStore = locationStore;
    }

    @Transactional(readOnly = true)
    public SummarySnapshot load(Long userId, Long walkId) {
        WalkJpaEntity walk = walkRepository.findOwnedByUser(walkId, userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.WALK_NOT_FOUND));
        return new SummarySnapshot(
                walk.getId(),
                walk.getDurationSeconds(),
                walk.getDistanceMeters(),
                walk.getStartedAt(),
                walk.getEndedAt(),
                List.copyOf(locationStore.findAll(walkId))
        );
    }

    public record SummarySnapshot(
            Long walkId,
            Integer durationSeconds,
            BigDecimal distanceMeters,
            Instant startedAt,
            Instant endedAt,
            List<WalkLocationStore.Point> points
    ) {
    }
}
