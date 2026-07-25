// 방 CRUD 엔드포인트 — 끝 슬래시 포함 경로·상태 코드가 기존 계약 그대로다
package com.weniv.falls.controller;

import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import com.weniv.falls.domain.Guardian;
import com.weniv.falls.dto.RoomRequest;
import com.weniv.falls.dto.RoomResponse;
import com.weniv.falls.service.RoomService;

@RestController
public class RoomController {

    private final RoomService roomService;

    public RoomController(RoomService roomService) {
        this.roomService = roomService;
    }

    @GetMapping("/api/rooms/")
    public List<RoomResponse> list(@AuthenticationPrincipal Guardian guardian) {
        return roomService.list(guardian).stream().map(RoomResponse::from).toList();
    }

    @PostMapping("/api/rooms/")
    public ResponseEntity<RoomResponse> create(@AuthenticationPrincipal Guardian guardian,
                                               @RequestBody RoomRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED)
            .body(RoomResponse.from(roomService.create(guardian, request)));
    }

    @GetMapping("/api/rooms/{id}/")
    public RoomResponse get(@AuthenticationPrincipal Guardian guardian, @PathVariable Long id) {
        return RoomResponse.from(roomService.get(guardian, id));
    }

    @PutMapping("/api/rooms/{id}/")
    public RoomResponse put(@AuthenticationPrincipal Guardian guardian, @PathVariable Long id,
                            @RequestBody RoomRequest request) {
        return RoomResponse.from(roomService.update(guardian, id, request, false));
    }

    @PatchMapping("/api/rooms/{id}/")
    public RoomResponse patch(@AuthenticationPrincipal Guardian guardian, @PathVariable Long id,
                              @RequestBody RoomRequest request) {
        return RoomResponse.from(roomService.update(guardian, id, request, true));
    }

    @DeleteMapping("/api/rooms/{id}/")
    public ResponseEntity<Void> delete(@AuthenticationPrincipal Guardian guardian,
                                       @PathVariable Long id) {
        roomService.delete(guardian, id);
        return ResponseEntity.noContent().build();   // 204
    }
}
