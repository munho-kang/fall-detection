// 푸시 기기 조회 — 토큰 유니크 기반 이전·소유자 발송 목록·해제
package com.weniv.falls.repository;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import com.weniv.falls.domain.PushDevice;

public interface PushDeviceRepository extends JpaRepository<PushDevice, Long> {
    Optional<PushDevice> findByToken(String token);
    List<PushDevice> findByGuardianId(Long guardianId);
    void deleteByGuardianIdAndToken(Long guardianId, String token);   // 호출부는 @Transactional 필요
}
