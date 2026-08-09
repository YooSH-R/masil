package com.ssafy.backend.walk.application;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.util.LinkedHashSet;
import java.util.Locale;
import java.util.Set;

@ConfigurationProperties(prefix = "walk.proposal-producer")
public class WalkProposalProducerProperties {

    private Duration dueAfter = Duration.ofHours(72);
    private Duration proposalTtl = Duration.ofMinutes(30);
    private Duration retryCooldown = Duration.ofHours(3);

    /**
     * 산책을 조르는 활동 시간대. 앱의 "산책 주기 설정" 안내 문구가 이 값을
     * 그대로 설명하므로 바꿀 때는 프론트 문구도 함께 맞춰야 한다.
     * 밤에도 제안이 필요한 테스트에서는 0~24 로 넓히면 된다.
     */
    private int activeStartHour = 8;
    private int activeEndHour = 22;

    /** 활동 시간대를 판정할 기준 시간대. */
    private ZoneId zone = ZoneId.of("Asia/Seoul");
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

    public int getActiveStartHour() {
        return activeStartHour;
    }

    public void setActiveStartHour(int activeStartHour) {
        this.activeStartHour = requireHour(activeStartHour, "active-start-hour");
    }

    public int getActiveEndHour() {
        return activeEndHour;
    }

    public void setActiveEndHour(int activeEndHour) {
        this.activeEndHour = requireHour(activeEndHour, "active-end-hour");
    }

    public ZoneId getZone() {
        return zone;
    }

    public void setZone(ZoneId zone) {
        if (zone == null) {
            throw new IllegalArgumentException("zone must not be null");
        }
        this.zone = zone;
    }

    boolean isSleeping(String mode) {
        return mode != null && sleepingModes.contains(normalize(mode));
    }

    /** 활동 시간대 안이면 참. 시작·끝이 같거나 뒤집혀 있으면 하루 종일로 본다. */
    boolean isWithinActiveHours(Instant now) {
        if (activeStartHour >= activeEndHour) {
            return true;
        }
        int hour = now.atZone(zone).getHour();
        return hour >= activeStartHour && hour < activeEndHour;
    }

    /**
     * 하루 산책 횟수에 대응하는 제안 간격.
     *
     * <p>활동 시간대(기본 08:00~22:00, 14시간)를 횟수로 나눈 값이다. 앱의 안내
     * 문구가 같은 계산을 보여주므로 둘이 어긋나면 사용자가 받는 알림과 화면
     * 설명이 달라진다.
     */
    Duration intervalFor(int dailyWalkCount) {
        if (dailyWalkCount < 1) {
            return dueAfter;
        }
        int windowMinutes = activeStartHour >= activeEndHour
                ? 24 * 60
                : (activeEndHour - activeStartHour) * 60;
        return Duration.ofMinutes(Math.max(1, windowMinutes / dailyWalkCount));
    }

    private static int requireHour(int value, String name) {
        if (value < 0 || value > 24) {
            throw new IllegalArgumentException(name + " must be between 0 and 24");
        }
        return value;
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
