// 토큰 조회 — PK가 key 문자열이라 findById(key)가 곧 토큰 대조다
package com.weniv.falls.repository;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import com.weniv.falls.domain.AuthToken;

public interface AuthTokenRepository extends JpaRepository<AuthToken, String> {
    Optional<AuthToken> findByGuardianId(Long guardianId);
}
