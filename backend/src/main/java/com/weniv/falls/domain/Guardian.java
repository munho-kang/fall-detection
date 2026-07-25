// 보호자 계정 — Django User의 대체 (username·password만 사용)
package com.weniv.falls.domain;

import java.time.Instant;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

@Entity
@Table(name = "guardian")
public class Guardian {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, length = 150, unique = true)
    private String username;

    @Column(nullable = false, length = 100)
    private String password;   // BCrypt 해시

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected Guardian() {}

    public Guardian(String username, String password) {
        this.username = username;
        this.password = password;
    }

    @PrePersist
    void onCreate() {
        if (createdAt == null) createdAt = Instant.now();
    }

    public Long getId() { return id; }
    public String getUsername() { return username; }
    public String getPassword() { return password; }
}
