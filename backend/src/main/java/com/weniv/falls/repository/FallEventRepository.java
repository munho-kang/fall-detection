// 낙상 이벤트 조회 — 소유자 필터·최신순·멱등 중복 조회
package com.weniv.falls.repository;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import com.weniv.falls.domain.FallEvent;

public interface FallEventRepository extends JpaRepository<FallEvent, Long> {
    List<FallEvent> findByGuardianIdOrderByIdDesc(Long guardianId);
    Optional<FallEvent> findByIdAndGuardianId(Long id, Long guardianId);
    Optional<FallEvent> findFirstByGuardianIdAndRoomNameAndRoomNumberAndOccurredAt(
        Long guardianId, String roomName, Integer roomNumber, Instant occurredAt);
}
