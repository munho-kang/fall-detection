// 웹 푸시 구독 기기 — token은 구독 JSON 문자열, 전역 유니크 (계정 전환 시 이전된다)
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
@Table(name = "push_device")
public class PushDevice {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "guardian_id", nullable = false)
    private Guardian guardian;

    @Column(nullable = false, length = 10)
    private String kind;

    @Column(nullable = false, unique = true, columnDefinition = "text")
    private String token;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected PushDevice() {}

    public PushDevice(Guardian guardian, String kind, String token) {
        this.guardian = guardian;
        this.kind = kind;
        this.token = token;
    }

    // update_or_create 등가 — 같은 토큰이 다른 계정에 있으면 현 사용자로 이전한다
    public void reassign(Guardian guardian, String kind) {
        this.guardian = guardian;
        this.kind = kind;
    }

    @PrePersist
    void onCreate() {
        if (createdAt == null) createdAt = Instant.now();
    }

    public Long getId() { return id; }
    public Guardian getGuardian() { return guardian; }
    public String getKind() { return kind; }
    public String getToken() { return token; }
}
