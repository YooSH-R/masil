package com.ssafy.backend.walk.application;

import com.ssafy.backend.walk.infrastructure.persistence.WalkLocationStore;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.List;

@Component
public class WalkLocationRequestHasher {

    public String hash(List<WalkLocationStore.Point> points) {
        StringBuilder canonical = new StringBuilder();
        for (WalkLocationStore.Point point : points) {
            canonical.append(point.sequence()).append('|')
                    .append(point.latitude().toPlainString()).append('|')
                    .append(point.longitude().toPlainString()).append('|')
                    .append(point.accuracy() == null
                            ? "null"
                            : point.accuracy().toPlainString())
                    .append('|').append(point.recordedAt()).append(';');
        }
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest(
                    canonical.toString().getBytes(StandardCharsets.UTF_8)
            ));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256을 사용할 수 없습니다.", exception);
        }
    }
}
