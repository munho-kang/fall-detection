// 보호자 조회 — 로그인·가입 중복 검사용
package com.weniv.falls.repository;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import com.weniv.falls.domain.Guardian;

public interface GuardianRepository extends JpaRepository<Guardian, Long> {
    Optional<Guardian> findByUsername(String username);
    boolean existsByUsername(String username);
}
