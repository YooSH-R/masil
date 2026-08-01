package com.ssafy.backend.robot.presentation;

import jakarta.validation.Validation;
import jakarta.validation.Validator;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class RobotPairingRequestValidationTest {

    private final Validator validator = Validation
            .buildDefaultValidatorFactory()
            .getValidator();

    @Test
    void acceptsUrlSafeQrTokenWithAtLeast256BitEncodingLength() {
        RobotPairingController.RobotPairingRequest request =
                new RobotPairingController.RobotPairingRequest(
                        1L,
                        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
                );

        assertTrue(validator.validate(request).isEmpty());
    }

    @Test
    void rejectsShortOrNonUrlSafeQrToken() {
        RobotPairingController.RobotPairingRequest shortToken =
                new RobotPairingController.RobotPairingRequest(
                        1L,
                        "short-token"
                );
        RobotPairingController.RobotPairingRequest invalidCharacters =
                new RobotPairingController.RobotPairingRequest(
                        1L,
                        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA!"
                );

        assertFalse(validator.validate(shortToken).isEmpty());
        assertFalse(validator.validate(invalidCharacters).isEmpty());
    }
}
