// 보호자 프로필 — "어르신께 전화" 번호 저장소, 접근 시 get-or-create
package com.weniv.falls.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.OneToOne;
import jakarta.persistence.Table;

@Entity
@Table(name = "guardian_profile")
public class GuardianProfile {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @OneToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "guardian_id", nullable = false, unique = true)
    private Guardian guardian;

    @Column(name = "elder_phone", nullable = false, length = 20)
    private String elderPhone = "";

    protected GuardianProfile() {}

    public GuardianProfile(Guardian guardian) {
        this.guardian = guardian;
    }

    public void updatePhone(String elderPhone) {
        this.elderPhone = elderPhone;
    }

    public Long getId() { return id; }
    public String getElderPhone() { return elderPhone; }
}
