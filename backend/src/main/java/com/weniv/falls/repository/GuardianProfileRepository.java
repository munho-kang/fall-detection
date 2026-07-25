// 보호자 프로필 조회 — get-or-create용
package com.weniv.falls.repository;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import com.weniv.falls.domain.GuardianProfile;

public interface GuardianProfileRepository extends JpaRepository<GuardianProfile, Long> {
    Optional<GuardianProfile> findByGuardianId(Long guardianId);
}
