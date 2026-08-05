package com.ssafy.backend.walk.diary;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Repository;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

@Repository
class WalkDiaryStore {

    private final JdbcTemplate jdbcTemplate;
    private final String localTestDeviceId;

    WalkDiaryStore(
            JdbcTemplate jdbcTemplate,
            @Value("${walk.diary.local-test-device-id:}")
            String localTestDeviceId
    ) {
        this.jdbcTemplate = jdbcTemplate;
        this.localTestDeviceId = localTestDeviceId.trim();
    }

    List<OwnedDevice> findActiveOwnedDevices(long userId) {
        List<OwnedDevice> devices = jdbcTemplate.query("""
                SELECT r.serial_number, pairing.paired_at,
                       EXISTS (
                         SELECT 1
                         FROM robot_pairings previous_pairing
                         JOIN pets previous_pet
                           ON previous_pet.id = previous_pairing.pet_id
                         WHERE previous_pairing.robot_id = pairing.robot_id
                           AND previous_pet.user_id <> pet.user_id
                       ) AS previously_owned_by_other
                FROM pets pet
                JOIN robot_pairings pairing
                  ON pairing.pet_id = pet.id
                 AND pairing.unpaired_at IS NULL
                JOIN robots r
                  ON r.id = pairing.robot_id
                WHERE pet.user_id = ?
                  AND pet.deleted_at IS NULL
                ORDER BY r.serial_number
                """,
                (rs, rowNum) -> new OwnedDevice(
                        rs.getString("serial_number"),
                        rs.getBoolean("previously_owned_by_other")
                                ? rs.getTimestamp("paired_at").toInstant()
                                : Instant.EPOCH
                ),
                userId
        );
        if (devices.isEmpty() && !localTestDeviceId.isBlank()) {
            return List.of(new OwnedDevice(localTestDeviceId, Instant.EPOCH));
        }
        return devices;
    }

    Optional<OwnedDevice> findActiveOwnedDevice(
            long userId,
            String deviceId
    ) {
        Optional<OwnedDevice> ownedDevice = jdbcTemplate.query("""
                SELECT r.serial_number, pairing.paired_at,
                       EXISTS (
                         SELECT 1
                         FROM robot_pairings previous_pairing
                         JOIN pets previous_pet
                           ON previous_pet.id = previous_pairing.pet_id
                         WHERE previous_pairing.robot_id = pairing.robot_id
                           AND previous_pet.user_id <> pet.user_id
                       ) AS previously_owned_by_other
                FROM pets pet
                JOIN robot_pairings pairing
                  ON pairing.pet_id = pet.id
                 AND pairing.unpaired_at IS NULL
                JOIN robots r
                  ON r.id = pairing.robot_id
                WHERE pet.user_id = ?
                  AND pet.deleted_at IS NULL
                  AND r.serial_number = ?
                """,
                (rs, rowNum) -> new OwnedDevice(
                        rs.getString("serial_number"),
                        rs.getBoolean("previously_owned_by_other")
                                ? rs.getTimestamp("paired_at").toInstant()
                                : Instant.EPOCH
                ),
                userId,
                deviceId
        ).stream().findFirst();
        if (ownedDevice.isEmpty()
                && !localTestDeviceId.isBlank()
                && localTestDeviceId.equals(deviceId)) {
            return Optional.of(new OwnedDevice(deviceId, Instant.EPOCH));
        }
        return ownedDevice;
    }

    record OwnedDevice(String deviceId, Instant visibleFrom) {
    }
}
