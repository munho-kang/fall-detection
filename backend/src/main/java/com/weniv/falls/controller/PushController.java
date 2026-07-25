// 푸시 기기 등록·해제 엔드포인트 (vapid-key는 발송 모듈과 함께 Task 6에서 추가)
package com.weniv.falls.controller;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import com.weniv.falls.domain.Guardian;
import com.weniv.falls.dto.PushDeviceDeleteRequest;
import com.weniv.falls.dto.PushDeviceRequest;
import com.weniv.falls.service.PushDeviceService;

@RestController
public class PushController {

    private final PushDeviceService pushDeviceService;

    public PushController(PushDeviceService pushDeviceService) {
        this.pushDeviceService = pushDeviceService;
    }

    @PostMapping("/api/push/devices/")
    public ResponseEntity<Void> register(@AuthenticationPrincipal Guardian guardian,
                                         @Valid @RequestBody PushDeviceRequest request) {
        pushDeviceService.register(guardian, request.kind(), request.token());
        return ResponseEntity.status(HttpStatus.CREATED).build();   // 201, 본문 없음 (기존 계약)
    }

    @DeleteMapping("/api/push/devices/")
    public ResponseEntity<Void> unregister(@AuthenticationPrincipal Guardian guardian,
                                           @RequestBody(required = false) PushDeviceDeleteRequest request) {
        // 없는 토큰·빈 본문이어도 204 — 로그아웃 흐름을 막지 않는다
        pushDeviceService.unregister(guardian, request == null ? null : request.token());
        return ResponseEntity.noContent().build();
    }
}
