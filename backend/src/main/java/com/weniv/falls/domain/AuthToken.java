// DRF authtoken 등가 — 보호자당 1개, 만료 없는 40자 hex 키 ("한 번 로그인하면 유지" 보존)
package com.weniv.falls.domain;

import java.security.SecureRandom;
import java.time.Instant;
import java.util.HexFormat;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.OneToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

@Entity
@Table(name = "auth_token")
public class AuthToken {

    @Id
    @Column(name = "key", length = 40)
    private String key;

    @OneToOne(optional = false)
    @JoinColumn(name = "guardian_id", nullable = false, unique = true)
    private Guardian guardian;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected AuthToken() {}

    public AuthToken(String key, Guardian guardian) {
        this.key = key;
        this.guardian = guardian;
    }

    // DRF Token.generate_key 등가 — os.urandom(20)의 hex 40자
    public static String newKey() {
        byte[] bytes = new byte[20];
        new SecureRandom().nextBytes(bytes);
        return HexFormat.of().formatHex(bytes);
    }

    @PrePersist
    void onCreate() {
        if (createdAt == null) createdAt = Instant.now();
    }

    public String getKey() { return key; }
    public Guardian getGuardian() { return guardian; }
}
