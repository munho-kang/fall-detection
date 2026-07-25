// 방 조회 — 소유자 필터·name,number 정렬·중복 사전 검사
package com.weniv.falls.repository;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import com.weniv.falls.domain.Room;

public interface RoomRepository extends JpaRepository<Room, Long> {
    List<Room> findByGuardianIdOrderByNameAscNumberAsc(Long guardianId);
    Optional<Room> findByIdAndGuardianId(Long id, Long guardianId);
    boolean existsByGuardianIdAndNameAndNumber(Long guardianId, String name, Integer number);
    boolean existsByGuardianIdAndNameAndNumberAndIdNot(Long guardianId, String name, Integer number, Long id);
}
