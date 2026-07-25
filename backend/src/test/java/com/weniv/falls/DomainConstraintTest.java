// 데이터 모델 제약 테스트 — 낙상 중복 금지·방 보호자별 유니크 (pytest Task 1 구획 포팅)
package com.weniv.falls;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Instant;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;

import com.weniv.falls.domain.FallEvent;
import com.weniv.falls.domain.Room;

class DomainConstraintTest extends IntegrationTestBase {

    @Test
    void fall_event_room_name_is_free_text() {
        // 고정 선택지(choices) 없이 임의 문자열 방 이름이 그대로 저장돼야 한다
        FallEvent e = makeEvent(guardian, "서재", 1);
        assertThat(fallEventRepository.findById(e.getId()).orElseThrow().getRoomName())
            .isEqualTo("서재");
    }

    @Test
    void fall_event_rejects_exact_duplicate() {
        Instant t = Instant.now();
        fallEventRepository.saveAndFlush(new FallEvent(guardian, "안방", 1, t, 0.9));
        assertThatThrownBy(() ->
            fallEventRepository.saveAndFlush(new FallEvent(guardian, "안방", 1, t, 0.8)))
            .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void room_unique_per_guardian() {
        roomRepository.saveAndFlush(new Room(guardian, "안방", 1));
        assertThatThrownBy(() -> roomRepository.saveAndFlush(new Room(guardian, "안방", 1)))
            .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void same_room_allowed_for_other_guardian() {
        roomRepository.saveAndFlush(new Room(guardian, "안방", 1));
        roomRepository.saveAndFlush(new Room(other, "안방", 1));   // 예외 없이 저장돼야 한다
    }
}
