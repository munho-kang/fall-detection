// 방 CRUD — 소유권 필터 조회(남의 방은 404), 중복 사전 검사 + 경합 안전망(둘 다 같은 400)
package com.weniv.falls.service;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;

import com.weniv.falls.domain.Guardian;
import com.weniv.falls.domain.Room;
import com.weniv.falls.dto.RoomRequest;
import com.weniv.falls.error.FieldValidationException;
import com.weniv.falls.error.NotFoundException;
import com.weniv.falls.repository.RoomRepository;

@Service
public class RoomService {

    public static final String DUPLICATE_ROOM_MESSAGE = "같은 이름과 번호의 방이 이미 있습니다.";
    private static final String REQUIRED_MESSAGE = "이 필드는 필수 항목입니다.";

    private final RoomRepository roomRepository;

    public RoomService(RoomRepository roomRepository) {
        this.roomRepository = roomRepository;
    }

    public List<Room> list(Guardian guardian) {
        return roomRepository.findByGuardianIdOrderByNameAscNumberAsc(guardian.getId());
    }

    public Room get(Guardian guardian, Long id) {
        // guardian 조건을 건 조회 — 남의 방은 존재 자체가 드러나지 않고 404가 된다
        return roomRepository.findByIdAndGuardianId(id, guardian.getId())
            .orElseThrow(NotFoundException::new);
    }

    public Room create(Guardian guardian, RoomRequest request) {
        validate(request, true);
        if (roomRepository.existsByGuardianIdAndNameAndNumber(
                guardian.getId(), request.name(), request.number())) {
            throw duplicate();
        }
        try {
            // saveAndFlush — 제약 위반을 이 자리에서 잡아 400으로 바꾸기 위해 즉시 flush한다
            return roomRepository.saveAndFlush(new Room(guardian, request.name(), request.number()));
        } catch (DataIntegrityViolationException e) {
            throw duplicate();   // 사전 검사와 저장 사이의 경합도 같은 400
        }
    }

    public Room update(Guardian guardian, Long id, RoomRequest request, boolean partial) {
        Room room = get(guardian, id);
        validate(request, !partial);
        String name = request.name() != null ? request.name() : room.getName();
        Integer number = request.number() != null ? request.number() : room.getNumber();
        if (roomRepository.existsByGuardianIdAndNameAndNumberAndIdNot(
                guardian.getId(), name, number, room.getId())) {
            throw duplicate();
        }
        room.rename(name, number);
        try {
            return roomRepository.saveAndFlush(room);
        } catch (DataIntegrityViolationException e) {
            throw duplicate();
        }
    }

    public void delete(Guardian guardian, Long id) {
        roomRepository.delete(get(guardian, id));
    }

    private FieldValidationException duplicate() {
        return new FieldValidationException(
            Map.of("non_field_errors", List.of(DUPLICATE_ROOM_MESSAGE)));
    }

    // requireAll=true(POST·PUT)면 누락도 에러, false(PATCH)면 보낸 필드만 검사한다
    private void validate(RoomRequest request, boolean requireAll) {
        Map<String, List<String>> errors = new LinkedHashMap<>();

        List<String> nameErrors = new ArrayList<>();
        if (request.name() == null) {
            if (requireAll) nameErrors.add(REQUIRED_MESSAGE);
        } else {
            if (request.name().isBlank()) nameErrors.add(REQUIRED_MESSAGE);
            if (request.name().length() > 20) {
                nameErrors.add("이 필드의 글자 수가 20 이하인지 확인하십시오.");
            }
        }

        List<String> numberErrors = new ArrayList<>();
        if (request.number() == null) {
            if (requireAll) numberErrors.add(REQUIRED_MESSAGE);
        } else if (request.number() < 0 || request.number() > 32767) {
            numberErrors.add("이 값이 0 이상 32767 이하인지 확인하십시오.");
        }

        if (!nameErrors.isEmpty()) errors.put("name", nameErrors);
        if (!numberErrors.isEmpty()) errors.put("number", numberErrors);
        if (!errors.isEmpty()) throw new FieldValidationException(errors);
    }
}
