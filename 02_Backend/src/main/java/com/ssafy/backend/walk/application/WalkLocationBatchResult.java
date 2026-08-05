package com.ssafy.backend.walk.application;

public record WalkLocationBatchResult(
        Long walkId,
        int receivedCount,
        int savedCount,
        int rejectedCount
) {
}
