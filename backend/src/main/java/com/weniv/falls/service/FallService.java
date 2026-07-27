// 낙상 등록·조회·확인·삭제 — 오프라인 큐 재전송 멱등성 (같은 낙상 재수신 → 기존 행에 신고 시각만 병합, 푸시 없음)
// 클래스 @Transactional을 쓰지 않는다: 제약 위반 후 재조회가 새 트랜잭션이어야 하기 때문 (Django autocommit 등가)
package com.weniv.falls.service;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;

import com.weniv.falls.domain.FallEvent;
import com.weniv.falls.domain.Guardian;
import com.weniv.falls.dto.FallEventRequest;
import com.weniv.falls.error.FieldValidationException;
import com.weniv.falls.error.NotFoundException;
import com.weniv.falls.repository.FallEventRepository;

@Service
public class FallService {

    public record CreateResult(FallEvent event, boolean created) {}

    public static final String UNACKNOWLEDGED_DELETE_MESSAGE = "확인하지 않은 낙상은 삭제할 수 없습니다.";

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
            return new CreateResult(merge(existing.get(), request), false);   // 재전송 — 푸시 없음
        }
        try {
            FallEvent event = new FallEvent(
                guardian, request.roomName(), request.roomNumber(), occurredAt,
                request.confidence());
            if (request.reported119At() != null) {
                event.markReported119(request.reported119At().toInstant());
            }
            if (request.voiceOkAt() != null) {
                event.markVoiceOk(request.voiceOkAt().toInstant());
            }
            return new CreateResult(fallEventRepository.saveAndFlush(event), true);
        } catch (DataIntegrityViolationException e) {
            // 생성 경합 — uniq_fall_dedup에 걸렸으면 재조회해 200 경로로
            return new CreateResult(
                merge(findDuplicate(guardian, request, occurredAt).orElseThrow(), request), false);
        }
    }

    // 시각 병합 — 각 필드는 기존 값이 null일 때만 쓴다 (mark*가 보장). 쓸 것이 없으면 저장도 없다.
    private FallEvent merge(FallEvent event, FallEventRequest request) {
        boolean changed = false;
        if (request.reported119At() != null && event.getReported119At() == null) {
            event.markReported119(request.reported119At().toInstant());
            changed = true;
        }
        if (request.voiceOkAt() != null && event.getVoiceOkAt() == null) {
            event.markVoiceOk(request.voiceOkAt().toInstant());
            changed = true;
        }
        return changed ? fallEventRepository.save(event) : event;
    }

    public FallEvent acknowledge(Guardian guardian, Long id) {
        // guardian까지 걸어 조회 — 남의 이벤트는 존재 자체가 드러나지 않고 404가 된다
        FallEvent event = fallEventRepository.findByIdAndGuardianId(id, guardian.getId())
            .orElseThrow(NotFoundException::new);
        event.acknowledgeNow();   // 첫 확인 시각 보존 (멱등)
        return fallEventRepository.save(event);
    }

    public void delete(Guardian guardian, Long id) {
        // 소유권을 먼저 본다 — 확인 여부를 먼저 보면 남의 미확인 기록에 400이 나가면서
        // "그 id는 존재하고 아직 미확인"이라는 사실이 새어나간다.
        FallEvent event = fallEventRepository.findByIdAndGuardianId(id, guardian.getId())
            .orElseThrow(NotFoundException::new);
        if (event.getAcknowledgedAt() == null) {
            throw new FieldValidationException(
                Map.of("non_field_errors", List.of(UNACKNOWLEDGED_DELETE_MESSAGE)));
        }
        fallEventRepository.delete(event);
    }

    private Optional<FallEvent> findDuplicate(Guardian guardian, FallEventRequest request,
                                              Instant occurredAt) {
        return fallEventRepository.findFirstByGuardianIdAndRoomNameAndRoomNumberAndOccurredAt(
            guardian.getId(), request.roomName(), request.roomNumber(), occurredAt);
    }
}
