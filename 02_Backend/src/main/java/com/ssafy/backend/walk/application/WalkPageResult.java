package com.ssafy.backend.walk.application;

import java.util.List;

public record WalkPageResult(
        List<WalkResult> items,
        String nextCursor,
        boolean hasNext
) {
}
