// 루트 헬스체크 — 서버 생존 확인용 JSON (기존 Django 응답과 동일)
package com.weniv.falls.controller;

import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HealthController {

    @GetMapping("/")
    public Map<String, String> health() {
        return Map.of("status", "ok", "service", "fall-detection-backend");
    }
}
