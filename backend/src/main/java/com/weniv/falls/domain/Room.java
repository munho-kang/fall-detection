// 방 — 보호자별 (name, number) 유니크
package com.weniv.falls.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

@Entity
@Table(name = "room")
public class Room {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "guardian_id", nullable = false)
    private Guardian guardian;

    @Column(nullable = false, length = 20)
    private String name;

    @Column(nullable = false)
    private Integer number;

    protected Room() {}

    public Room(Guardian guardian, String name, Integer number) {
        this.guardian = guardian;
        this.name = name;
        this.number = number;
    }

    public void rename(String name, Integer number) {
        this.name = name;
        this.number = number;
    }

    public Long getId() { return id; }
    public Guardian getGuardian() { return guardian; }
    public String getName() { return name; }
    public Integer getNumber() { return number; }
}
