package com.ssafy.backend.robot.image;

import com.ssafy.backend.robot.image.RobotImageController.ImageResponse;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

@Repository
public class RobotImageStore {

    private final JdbcTemplate jdbcTemplate;

    public RobotImageStore(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    long requireRobotId(String deviceId) {
        List<Long> ids = jdbcTemplate.query(
                "SELECT id FROM robots WHERE serial_number = ?",
                (rs, rowNum) -> rs.getLong("id"),
                deviceId
        );
        if (ids.size() != 1) {
            throw new IllegalArgumentException("등록되지 않은 deviceId입니다.");
        }
        return ids.get(0);
    }

    void createPending(
            UUID id,
            long robotId,
            String objectKey,
            String contentType,
            long expectedSize,
            Instant capturedAt,
            Instant expiresAt
    ) {
        jdbcTemplate.update("""
                INSERT INTO robot_photos (
                    id, robot_id, object_key, mime_type, expected_size_bytes,
                    captured_at, upload_expires_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                id,
                robotId,
                objectKey,
                contentType,
                expectedSize,
                Timestamp.from(capturedAt),
                Timestamp.from(expiresAt)
        );
    }

    StoredImage requirePending(String deviceId, UUID imageId) {
        List<StoredImage> images = jdbcTemplate.query("""
                SELECT p.id, r.serial_number, p.object_key, p.mime_type,
                       p.expected_size_bytes, p.captured_at, p.uploaded_at
                FROM robot_photos p
                JOIN robots r ON r.id = p.robot_id
                WHERE p.id = ? AND r.serial_number = ?
                  AND p.upload_status = 'PENDING'
                  AND p.upload_expires_at > CURRENT_TIMESTAMP
                """,
                (rs, rowNum) -> map(rs),
                imageId,
                deviceId
        );
        if (images.size() != 1) {
            throw new IllegalArgumentException(
                    "완료할 수 없는 이미지 업로드입니다."
            );
        }
        return images.get(0);
    }

    StoredImage requireUploaded(Long userId, UUID imageId) {
        List<StoredImage> images = jdbcTemplate.query("""
                SELECT p.id, r.serial_number, p.object_key, p.mime_type,
                       p.expected_size_bytes, p.captured_at, p.uploaded_at
                FROM robot_photos p
                JOIN robots r ON r.id = p.robot_id
                JOIN robot_pairings pairing ON pairing.robot_id = r.id
                JOIN pets pet ON pet.id = pairing.pet_id
                WHERE p.id = ? AND p.upload_status = 'UPLOADED'
                  AND pairing.unpaired_at IS NULL
                  AND pet.user_id = ?
                  AND pet.deleted_at IS NULL
                """,
                (rs, rowNum) -> map(rs),
                imageId,
                userId
        );
        if (images.size() != 1) {
            throw new IllegalArgumentException("조회할 수 없는 이미지입니다.");
        }
        return images.get(0);
    }

    void requirePetOwnership(Long userId, Long petId) {
        Integer count = jdbcTemplate.queryForObject("""
                SELECT COUNT(*)
                FROM pets
                WHERE id = ? AND user_id = ? AND deleted_at IS NULL
                """,
                Integer.class,
                petId,
                userId
        );
        if (count == null || count != 1) {
            throw new IllegalArgumentException("조회할 수 없는 펫입니다.");
        }
    }

    void markUploaded(UUID imageId, long actualSize, Instant uploadedAt) {
        jdbcTemplate.update("""
                UPDATE robot_photos
                SET upload_status = 'UPLOADED',
                    actual_size_bytes = ?,
                    uploaded_at = ?
                WHERE id = ?
                """,
                actualSize,
                Timestamp.from(uploadedAt),
                imageId
        );
    }

    List<ImageResponse> findUploadedByPetId(Long petId) {
        return jdbcTemplate.query("""
                SELECT p.id, r.serial_number, p.object_key, p.mime_type,
                       p.actual_size_bytes, p.captured_at, p.uploaded_at
                FROM robot_photos p
                JOIN robots r ON r.id = p.robot_id
                JOIN robot_pairings pairing ON pairing.robot_id = r.id
                WHERE pairing.pet_id = ? AND pairing.unpaired_at IS NULL
                  AND p.upload_status = 'UPLOADED'
                ORDER BY p.captured_at DESC
                """,
                (rs, rowNum) -> new ImageResponse(
                        rs.getObject("id", UUID.class),
                        rs.getString("serial_number"),
                        rs.getString("object_key"),
                        rs.getString("mime_type"),
                        rs.getObject("actual_size_bytes", Long.class),
                        rs.getTimestamp("captured_at").toInstant(),
                        rs.getTimestamp("uploaded_at").toInstant()
                ),
                petId
        );
    }

    private StoredImage map(java.sql.ResultSet rs)
            throws java.sql.SQLException {
        Timestamp uploadedAt = rs.getTimestamp("uploaded_at");
        return new StoredImage(
                rs.getObject("id", UUID.class),
                rs.getString("serial_number"),
                rs.getString("object_key"),
                rs.getString("mime_type"),
                rs.getLong("expected_size_bytes"),
                rs.getTimestamp("captured_at").toInstant(),
                uploadedAt == null ? null : uploadedAt.toInstant()
        );
    }

    record StoredImage(
            UUID id,
            String deviceId,
            String objectKey,
            String contentType,
            long expectedSize,
            Instant capturedAt,
            Instant uploadedAt
    ) {
        ImageResponse toResponse(long actualSize, Instant completedAt) {
            return new ImageResponse(
                    id,
                    deviceId,
                    objectKey,
                    contentType,
                    actualSize,
                    capturedAt,
                    completedAt
            );
        }
    }
}
