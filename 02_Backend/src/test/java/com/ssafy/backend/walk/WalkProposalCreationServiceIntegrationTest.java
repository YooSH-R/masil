package com.ssafy.backend.walk;

import com.ssafy.backend.walk.application.WalkProposalCreationOutcome;
import com.ssafy.backend.walk.application.WalkProposalCreationService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Set;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

@SpringBootTest
class WalkProposalCreationServiceIntegrationTest {

    private static final long USER_ID = 181_001L;
    private static final long PET_ID = 182_001L;
    private static final long ROBOT_ID = 183_001L;
    private static final long PAIRING_ID = 184_001L;
    private static final Instant NOW = Instant.parse("2026-08-02T00:00:00Z");

    @Autowired
    private WalkProposalCreationService creationService;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    private ExecutorService executor;

    @BeforeEach
    void setUp() {
        clearData();
        insertActivePairing("IDLE");
    }

    @AfterEach
    void tearDown() {
        if (executor != null) {
            executor.shutdownNow();
        }
    }

    @Test
    void createsThirtyMinuteProposalWhenRobotHasNoCompletedWalk() {
        WalkProposalCreationOutcome outcome =
                creationService.createIfDueForRobot(ROBOT_ID, NOW);

        assertEquals(WalkProposalCreationOutcome.CREATED, outcome);
        ProposalRow proposal = jdbcTemplate.queryForObject(
                """
                SELECT status, message, proposed_at, expires_at
                FROM walk_proposals
                WHERE robot_pairing_id = ?
                """,
                (rs, rowNum) -> new ProposalRow(
                        rs.getString("status"),
                        rs.getString("message"),
                        rs.getTimestamp("proposed_at").toInstant(),
                        rs.getTimestamp("expires_at").toInstant()
                ),
                PAIRING_ID
        );
        assertEquals("PENDING", proposal.status());
        assertEquals("오랫동안 산책하지 않았어요. 함께 산책해요.", proposal.message());
        assertEquals(NOW, proposal.proposedAt());
        assertEquals(NOW.plus(Duration.ofMinutes(30)), proposal.expiresAt());
    }

    @Test
    void repeatedAndConcurrentCallsLeaveOnlyOnePendingProposal()
            throws Exception {
        executor = Executors.newFixedThreadPool(2);
        CountDownLatch ready = new CountDownLatch(2);
        CountDownLatch start = new CountDownLatch(1);

        Future<WalkProposalCreationOutcome> first = executor.submit(
                () -> createAfterBarrier(ready, start)
        );
        Future<WalkProposalCreationOutcome> second = executor.submit(
                () -> createAfterBarrier(ready, start)
        );
        assertTrue(ready.await(5, TimeUnit.SECONDS));
        start.countDown();

        Set<WalkProposalCreationOutcome> outcomes = Set.of(
                first.get(5, TimeUnit.SECONDS),
                second.get(5, TimeUnit.SECONDS)
        );
        assertEquals(Set.of(
                WalkProposalCreationOutcome.CREATED,
                WalkProposalCreationOutcome.ALREADY_PENDING
        ), outcomes);
        assertEquals(1, pendingProposalCount());
        assertEquals(
                WalkProposalCreationOutcome.ALREADY_PENDING,
                creationService.createIfDueForRobot(ROBOT_ID, NOW)
        );
        assertEquals(1, pendingProposalCount());
    }

    @ParameterizedTest
    @ValueSource(strings = {"SLEEP", "sleeping", " AsLeEp "})
    void skipsSleepingRobotModes(String mode) {
        jdbcTemplate.update(
                "UPDATE robot_current_states SET mode = ? WHERE robot_id = ?",
                mode,
                ROBOT_ID
        );

        assertEquals(
                WalkProposalCreationOutcome.ROBOT_SLEEPING,
                creationService.createIfDueForRobot(ROBOT_ID, NOW)
        );
        assertEquals(0, pendingProposalCount());
    }

    @Test
    void skipsPairingWithCompletedWalkInsideSeventyTwoHours() {
        insertCompletedWalk(NOW.minus(Duration.ofHours(71)));

        assertEquals(
                WalkProposalCreationOutcome.RECENT_WALK,
                creationService.createIfDueForRobot(ROBOT_ID, NOW)
        );
        assertEquals(0, pendingProposalCount());
    }

    @Test
    void createsProposalWhenLastCompletedWalkIsSeventyTwoHoursOld() {
        insertCompletedWalk(NOW.minus(Duration.ofHours(72)));

        assertEquals(
                WalkProposalCreationOutcome.CREATED,
                creationService.createIfDueForRobot(ROBOT_ID, NOW)
        );
        assertEquals(1, pendingProposalCount());
    }

    @Test
    void skipsAcceptedProposalUntilItsWalkIsCreated() {
        jdbcTemplate.update(
                """
                INSERT INTO walk_proposals (
                    robot_pairing_id, message, status,
                    proposed_at, expires_at, responded_at
                ) VALUES (?, 'walk', 'ACCEPTED', ?, ?, ?)
                """,
                PAIRING_ID,
                Timestamp.from(NOW.minusSeconds(60)),
                Timestamp.from(NOW.plusSeconds(60)),
                Timestamp.from(NOW)
        );

        assertEquals(
                WalkProposalCreationOutcome.ACCEPTED_PROPOSAL_AWAITING_WALK,
                creationService.createIfDueForRobot(ROBOT_ID, NOW)
        );
        assertEquals(0, pendingProposalCount());
    }

    @Test
    void expiredAcceptedProposalDoesNotBlockNextProposal() {
        jdbcTemplate.update(
                """
                INSERT INTO walk_proposals (
                    robot_pairing_id, message, status,
                    proposed_at, expires_at, responded_at
                ) VALUES (?, 'old accepted walk', 'ACCEPTED', ?, ?, ?)
                """,
                PAIRING_ID,
                Timestamp.from(NOW.minusSeconds(120)),
                Timestamp.from(NOW.minusSeconds(60)),
                Timestamp.from(NOW.minusSeconds(90))
        );

        assertEquals(
                WalkProposalCreationOutcome.CREATED,
                creationService.createIfDueForRobot(ROBOT_ID, NOW)
        );
        assertEquals(1, pendingProposalCount());
    }

    @Test
    void expiresDuePendingAndCreatesReplacementInSameTransaction() {
        jdbcTemplate.update(
                """
                INSERT INTO walk_proposals (
                    robot_pairing_id, message, status, proposed_at, expires_at
                ) VALUES (?, 'expired walk', 'PENDING', ?, ?)
                """,
                PAIRING_ID,
                Timestamp.from(NOW.minusSeconds(120)),
                Timestamp.from(NOW.minusSeconds(60))
        );

        assertEquals(
                WalkProposalCreationOutcome.CREATED,
                creationService.createIfDueForRobot(ROBOT_ID, NOW)
        );
        assertEquals(1, pendingProposalCount());
        assertEquals(
                1,
                jdbcTemplate.queryForObject(
                        """
                        SELECT COUNT(*) FROM walk_proposals
                        WHERE robot_pairing_id = ? AND status = 'EXPIRED'
                        """,
                        Integer.class,
                        PAIRING_ID
                )
        );
    }

    @Test
    void skipsOpenWalkAndInactivePairing() {
        jdbcTemplate.update(
                """
                INSERT INTO walks (
                    robot_pairing_id, status, created_at, updated_at
                ) VALUES (?, 'READY', ?, ?)
                """,
                PAIRING_ID,
                Timestamp.from(NOW.minusSeconds(60)),
                Timestamp.from(NOW.minusSeconds(60))
        );
        assertEquals(
                WalkProposalCreationOutcome.WALK_IN_PROGRESS,
                creationService.createIfDueForRobot(ROBOT_ID, NOW)
        );

        jdbcTemplate.update("DELETE FROM walks");
        jdbcTemplate.update(
                "UPDATE robot_pairings SET unpaired_at = ? WHERE id = ?",
                Timestamp.from(NOW),
                PAIRING_ID
        );
        assertEquals(
                WalkProposalCreationOutcome.ACTIVE_PAIRING_NOT_FOUND,
                creationService.createIfDueForRobot(ROBOT_ID, NOW)
        );
        assertEquals(0, pendingProposalCount());
    }

    private WalkProposalCreationOutcome createAfterBarrier(
            CountDownLatch ready,
            CountDownLatch start
    ) throws InterruptedException {
        ready.countDown();
        start.await();
        return creationService.createIfDueForRobot(ROBOT_ID, NOW);
    }

    private int pendingProposalCount() {
        Integer count = jdbcTemplate.queryForObject(
                """
                SELECT COUNT(*)
                FROM walk_proposals
                WHERE robot_pairing_id = ? AND status = 'PENDING'
                """,
                Integer.class,
                PAIRING_ID
        );
        return count == null ? 0 : count;
    }

    private void insertCompletedWalk(Instant endedAt) {
        jdbcTemplate.update(
                """
                INSERT INTO walks (
                    robot_pairing_id, status, started_at, ended_at,
                    distance_meters, duration_seconds, created_at, updated_at
                ) VALUES (?, 'COMPLETED', ?, ?, 100.00, 600, ?, ?)
                """,
                PAIRING_ID,
                Timestamp.from(endedAt.minusSeconds(600)),
                Timestamp.from(endedAt),
                Timestamp.from(endedAt.minusSeconds(600)),
                Timestamp.from(endedAt)
        );
    }

    private void insertActivePairing(String mode) {
        jdbcTemplate.update(
                """
                INSERT INTO users (id, version, nickname, created_at, updated_at)
                VALUES (?, 0, 'walk-proposal-user', ?, ?)
                """,
                USER_ID,
                Timestamp.from(NOW.minus(Duration.ofDays(10))),
                Timestamp.from(NOW.minus(Duration.ofDays(10)))
        );
        jdbcTemplate.update(
                """
                INSERT INTO pets (id, user_id, name, created_at, updated_at)
                VALUES (?, ?, 'walk-proposal-pet', ?, ?)
                """,
                PET_ID,
                USER_ID,
                Timestamp.from(NOW.minus(Duration.ofDays(10))),
                Timestamp.from(NOW.minus(Duration.ofDays(10)))
        );
        jdbcTemplate.update(
                """
                INSERT INTO robots (
                    id, serial_number, model_name, owner_user_id,
                    ownership_claimed_at, updated_at
                ) VALUES (?, 'WALK-PROPOSAL-ROBOT', 'MYSIL-WALK', ?, ?, ?)
                """,
                ROBOT_ID,
                USER_ID,
                Timestamp.from(NOW.minus(Duration.ofDays(10))),
                Timestamp.from(NOW.minus(Duration.ofDays(10)))
        );
        jdbcTemplate.update(
                """
                INSERT INTO robot_pairings (
                    id, pet_id, robot_id, paired_at
                ) VALUES (?, ?, ?, ?)
                """,
                PAIRING_ID,
                PET_ID,
                ROBOT_ID,
                Timestamp.from(NOW.minus(Duration.ofDays(10)))
        );
        jdbcTemplate.update(
                """
                INSERT INTO robot_current_states (
                    robot_id, online, mode, battery_level,
                    docked, last_seen_at, updated_at
                ) VALUES (?, TRUE, ?, 80, FALSE, ?, ?)
                """,
                ROBOT_ID,
                mode,
                Timestamp.from(NOW),
                Timestamp.from(NOW)
        );
    }

    private void clearData() {
        jdbcTemplate.execute("SET REFERENTIAL_INTEGRITY FALSE");
        for (String table : List.of(
                "walk_location_batch_requests",
                "walk_locations",
                "walks",
                "walk_proposals",
                "robot_current_states",
                "robot_pairings",
                "robot_credentials",
                "robots",
                "pet_affinity_states",
                "pets",
                "users"
        )) {
            jdbcTemplate.execute("TRUNCATE TABLE " + table);
        }
        jdbcTemplate.execute("SET REFERENTIAL_INTEGRITY TRUE");
    }

    private record ProposalRow(
            String status,
            String message,
            Instant proposedAt,
            Instant expiresAt
    ) {
    }
}
