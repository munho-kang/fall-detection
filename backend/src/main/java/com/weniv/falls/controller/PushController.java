// 푸시 기기 등록·해제·VAPID 공개키 조회 엔드포인트
package com.weniv.falls.controller;

import java.util.Map;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import com.weniv.falls.domain.Guardian;
import com.weniv.falls.dto.PushDeviceDeleteRequest;
import com.weniv.falls.dto.PushDeviceRequest;
import com.weniv.falls.dto.VapidKeyResponse;
import com.weniv.falls.service.PushDeviceService;
import com.weniv.falls.service.VapidService;

@RestController
public class PushController {

    private final PushDeviceService pushDeviceService;
    private final VapidService vapidService;

    public PushController(PushDeviceService pushDeviceService, VapidService vapidService) {
        this.pushDeviceService = pushDeviceService;
        this.vapidService = vapidService;
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

    @GetMapping("/api/push/vapid-key/")
    public ResponseEntity<?> vapidKey() {
        String key = vapidService.publicKey();
        if (key == null) {
            // 문자열 고정 (스펙 8절) — 보호자 페이지가 이 503으로 "미설정" 안내를 띄운다
            return ResponseEntity.status(503).body(Map.of("detail", "웹 푸시가 설정되지 않았습니다."));
        }
        return ResponseEntity.ok(new VapidKeyResponse(key));
    }
}
