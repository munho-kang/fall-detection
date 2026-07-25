// 낙상 등록·조회·확인 — 오프라인 큐 재전송 멱등성 (같은 낙상 재수신 → 기존 행, 푸시 없음)
// 클래스 @Transactional을 쓰지 않는다: 제약 위반 후 재조회가 새 트랜잭션이어야 하기 때문 (Django autocommit 등가)
package com.weniv.falls.service;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;

import com.weniv.falls.domain.FallEvent;
import com.weniv.falls.domain.Guardian;
import com.weniv.falls.dto.FallEventRequest;
import com.weniv.falls.error.NotFoundException;
import com.weniv.falls.repository.FallEventRepository;

@Service
public class FallService {

    public record CreateResult(FallEvent event, boolean created) {}

    private final FallEventRepository fallEventRepository;

    public FallService(FallEventRepository fallEventRepository) {
        this.fallEventRepository = fallEventRepository;
    }

    public List<FallEvent> list(Guardian guardian) {
        // 남의 이벤트가 절대 새어나가지 않도록 요청자로 필터링한다
        return fallEventRepository.findByGuardianIdOrderByIdDesc(guardian.getId());
    }

    public CreateResult create(Guardian guardian, FallEventRequest request) {
        Instant occurredAt = request.occurredAt().toInstant();   // 오프셋 입력 → UTC 변환 저장

        Optional<FallEvent> existing = findDuplicate(guardian, request, occurredAt);
        if (existing.isPresent()) {
            return new CreateResult(existing.get(), false);   // 재전송 — 기존 행을 돌려주고 푸시 없음
        }
        try {
            FallEvent saved = fallEventRepository.saveAndFlush(new FallEvent(
                guardian, request.roomName(), request.roomNumber(), occurredAt,
                request.confidence()));
            return new CreateResult(saved, true);
        } catch (DataIntegrityViolationException e) {
            // 생성 경합 — uniq_fall_dedup에 걸렸으면 재조회해 200 경로로
            return new CreateResult(findDuplicate(guardian, request, occurredAt).orElseThrow(), false);
        }
    }

    public FallEvent acknowledge(Guardian guardian, Long id) {
        // guardian까지 걸어 조회 — 남의 이벤트는 존재 자체가 드러나지 않고 404가 된다
        FallEvent event = fallEventRepository.findByIdAndGuardianId(id, guardian.getId())
            .orElseThrow(NotFoundException::new);
        event.acknowledgeNow();   // 첫 확인 시각 보존 (멱등)
        return fallEventRepository.save(event);
    }

    private Optional<FallEvent> findDuplicate(Guardian guardian, FallEventRequest request,
                                              Instant occurredAt) {
        return fallEventRepository.findFirstByGuardianIdAndRoomNameAndRoomNumberAndOccurredAt(
            guardian.getId(), request.roomName(), request.roomNumber(), occurredAt);
    }
}
