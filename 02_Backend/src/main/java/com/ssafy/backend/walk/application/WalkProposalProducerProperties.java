package com.ssafy.backend.walk.application;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.time.Duration;
import java.util.LinkedHashSet;
import java.util.Locale;
import java.util.Set;

@ConfigurationProperties(prefix = "walk.proposal-producer")
public class WalkProposalProducerProperties {

    private Duration dueAfter = Duration.ofHours(72);
    private Duration proposalTtl = Duration.ofMinutes(30);
    private Duration retryCooldown = Duration.ofHours(3);
    private Set<String> sleepingModes = new LinkedHashSet<>(Set.of(
            "SLEEP",
            "SLEEPING",
            "ASLEEP"
    ));

    public Duration getDueAfter() {
        return dueAfter;
    }

    public void setDueAfter(Duration dueAfter) {
        this.dueAfter = requirePositive(dueAfter, "due-after");
    }

    public Duration getProposalTtl() {
        return proposalTtl;
    }

    public void setProposalTtl(Duration proposalTtl) {
        this.proposalTtl = requirePositive(proposalTtl, "proposal-ttl");
    }

    public Duration getRetryCooldown() {
        return retryCooldown;
    }

    public void setRetryCooldown(Duration retryCooldown) {
        this.retryCooldown = requirePositive(
                retryCooldown,
                "retry-cooldown"
        );
    }

    public Set<String> getSleepingModes() {
        return sleepingModes;
    }

    public void setSleepingModes(Set<String> sleepingModes) {
        if (sleepingModes == null) {
            throw new IllegalArgumentException("sleeping-modes must not be null");
        }
        LinkedHashSet<String> normalized = new LinkedHashSet<>();
        for (String mode : sleepingModes) {
            if (mode != null && !mode.isBlank()) {
                normalized.add(normalize(mode));
            }
        }
        this.sleepingModes = normalized;
    }

    boolean isSleeping(String mode) {
        return mode != null && sleepingModes.contains(normalize(mode));
    }

    private static Duration requirePositive(Duration value, String name) {
        if (value == null || value.isZero() || value.isNegative()) {
            throw new IllegalArgumentException(name + " must be positive");
        }
        return value;
    }

    private static String normalize(String mode) {
        return mode.trim().toUpperCase(Locale.ROOT);
    }
}
