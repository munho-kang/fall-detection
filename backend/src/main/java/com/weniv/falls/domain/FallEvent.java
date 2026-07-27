// 낙상 이벤트 — 방 정보는 문자열 스냅샷, (guardian, room, number, occurred_at) 유니크가 멱등성 근거
package com.weniv.falls.domain;

import java.time.Instant;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

@Entity
@Table(name = "fall_event")
public class FallEvent {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "guardian_id", nullable = false)
    private Guardian guardian;

    @Column(name = "room_name", nullable = false, length = 20)
    private String roomName;

    @Column(name = "room_number", nullable = false)
    private Integer roomNumber;

    @Column(name = "occurred_at", nullable = false)
    private Instant occurredAt;   // 클라이언트가 판정한 낙상 시각 (FALLING 진입 시각)

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(nullable = false)
    private Double confidence;    // 판정 시점 랜드마크 4개의 visibility 평균

    @Column(name = "acknowledged_at")
    private Instant acknowledgedAt;

    @Column(name = "reported_119_at")
    private Instant reported119At;

    @Column(name = "voice_ok_at")
    private Instant voiceOkAt;

    protected FallEvent() {}

    public FallEvent(Guardian guardian, String roomName, Integer roomNumber,
                     Instant occurredAt, Double confidence) {
        this.guardian = guardian;
        this.roomName = roomName;
        this.roomNumber = roomNumber;
        this.occurredAt = occurredAt;
        this.confidence = confidence;
    }

    @PrePersist
    void onCreate() {
        if (createdAt == null) createdAt = Instant.now();
    }

    // 첫 확인 시각을 보존한다 — 두 번째 호출부터는 무시 (멱등)
    // 마이크로초 절단: PG timestamptz 정밀도와 맞춰, 응답 직렬화(메모리 값)와 재조회 값이 항상 같게 한다
    public void acknowledgeNow() {
        if (acknowledgedAt == null) {
            acknowledgedAt = Instant.now().truncatedTo(java.time.temporal.ChronoUnit.MICROS);
        }
    }

    // 첫 신고 시각을 보존한다 — 이미 값이 있으면 무시 (acknowledgeNow와 같은 멱등 패턴)
    // 마이크로초 절단도 같은 이유다: 응답 직렬화 값과 재조회 값이 항상 같아야 한다
    public void markReported119(Instant at) {
        if (reported119At == null && at != null) {
            reported119At = at.truncatedTo(java.time.temporal.ChronoUnit.MICROS);
        }
    }

    // 낙상자가 "괜찮아"라고 답한 첫 시각을 보존한다 — markReported119와 같은 멱등 패턴
    public void markVoiceOk(Instant at) {
        if (voiceOkAt == null && at != null) {
            voiceOkAt = at.truncatedTo(java.time.temporal.ChronoUnit.MICROS);
        }
    }

    public Long getId() { return id; }
    public Guardian getGuardian() { return guardian; }
    public String getRoomName() { return roomName; }
    public Integer getRoomNumber() { return roomNumber; }
    public Instant getOccurredAt() { return occurredAt; }
    public Instant getCreatedAt() { return createdAt; }
    public Double getConfidence() { return confidence; }
    public Instant getAcknowledgedAt() { return acknowledgedAt; }
    public Instant getReported119At() { return reported119At; }
    public Instant getVoiceOkAt() { return voiceOkAt; }
}
