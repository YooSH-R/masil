package com.ssafy.backend.pet.infrastructure.persistence;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.OneToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import org.hibernate.annotations.ColumnDefault;

import java.time.Instant;

@Entity
@Table(name = "pets")
public class PetJpaEntity {

    public static final int DEFAULT_DAILY_WALK_COUNT = 2;
    public static final int MIN_DAILY_WALK_COUNT = 1;

    /**
     * 산책일지 S3 경로가 {@code .../{yyyy-MM-dd}/session{1~6}/} 이라 하루 7회
     * 이상은 담을 자리가 없다. 더 열어두면 7번째 산책부터 일지가 조용히
     * 사라진다. DB 제약(pets_daily_walk_count_check)도 같은 값이다.
     */
    public static final int MAX_DAILY_WALK_COUNT = 6;

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(nullable = false, length = 100)
    private String name;

    @Column(name = "profile_image_key", length = 500)
    private String profileImageKey;

    /**
     * 하루 산책 횟수. 산책 제안 간격을 정하는 유일한 사용자 설정이다
     * (활동 시간대를 이 횟수로 나눈 값이 제안 간격이 된다).
     */
    @Column(name = "daily_walk_count", nullable = false)
    @ColumnDefault("2")
    private int dailyWalkCount = DEFAULT_DAILY_WALK_COUNT;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Column(name = "deleted_at")
    private Instant deletedAt;

    @OneToOne(
            mappedBy = "pet",
            fetch = FetchType.LAZY,
            cascade = CascadeType.ALL,
            orphanRemoval = true,
            optional = false
    )
    private PetAffinityStateJpaEntity affinityState;

    protected PetJpaEntity() {
    }

    public PetJpaEntity(Long userId, String name) {
        this.userId = userId;
        this.name = name;
        this.affinityState = PetAffinityStateJpaEntity.initial(this);
    }

    @PrePersist
    void onCreate() {
        Instant now = Instant.now();
        createdAt = now;
        updatedAt = now;
    }

    @PreUpdate
    void onUpdate() {
        updatedAt = Instant.now();
    }

    public Long getId() {
        return id;
    }

    public Long getUserId() {
        return userId;
    }

    public String getName() {
        return name;
    }

    public String getProfileImageKey() {
        return profileImageKey;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public PetAffinityStateJpaEntity getAffinityState() {
        return affinityState;
    }

    public void changeName(String name) {
        this.name = name;
    }

    public int getDailyWalkCount() {
        return dailyWalkCount;
    }

    /**
     * 허용 범위를 벗어난 값은 DB CHECK 제약(pets_daily_walk_count_check)에서
     * 어차피 막히므로, 원인을 알기 쉬운 지점에서 먼저 걸러낸다.
     */
    public void changeDailyWalkCount(int dailyWalkCount) {
        if (dailyWalkCount < MIN_DAILY_WALK_COUNT
                || dailyWalkCount > MAX_DAILY_WALK_COUNT) {
            throw new IllegalArgumentException(
                    "하루 산책 횟수는 " + MIN_DAILY_WALK_COUNT + "~"
                            + MAX_DAILY_WALK_COUNT + " 사이여야 합니다."
            );
        }
        this.dailyWalkCount = dailyWalkCount;
    }

    public void softDelete(Instant now) {
        deletedAt = now;
        updatedAt = now;
    }
}
