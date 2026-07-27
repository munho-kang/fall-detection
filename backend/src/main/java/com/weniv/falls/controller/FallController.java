// 낙상 엔드포인트 — 신규 201 + 비동기 푸시 / 중복 200 + 푸시 없음
package com.weniv.falls.controller;

import java.util.List;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import com.weniv.falls.domain.Guardian;
import com.weniv.falls.dto.FallEventRequest;
import com.weniv.falls.dto.FallEventResponse;
import com.weniv.falls.service.FallService;
import com.weniv.falls.service.PushService;

@RestController
public class FallController {

    private final FallService fallService;
    private final PushService pushService;

    public FallController(FallService fallService, PushService pushService) {
        this.fallService = fallService;
        this.pushService = pushService;
    }

    @GetMapping("/api/falls/")
    public List<FallEventResponse> list(@AuthenticationPrincipal Guardian guardian) {
        return fallService.list(guardian).stream().map(FallEventResponse::from).toList();
    }

    @PostMapping("/api/falls/")
    public ResponseEntity<FallEventResponse> create(@AuthenticationPrincipal Guardian guardian,
                                                    @Valid @RequestBody FallEventRequest request) {
        FallService.CreateResult result = fallService.create(guardian, request);
        if (result.created()) {
            pushService.sendToGuardianAsync(result.event());   // 201일 때만 발송
        }
        return ResponseEntity.status(result.created() ? HttpStatus.CREATED : HttpStatus.OK)
            .body(FallEventResponse.from(result.event()));
    }

    @PostMapping("/api/falls/{id}/acknowledge/")
    public FallEventResponse acknowledge(@AuthenticationPrincipal Guardian guardian,
                                         @PathVariable Long id) {
        return FallEventResponse.from(fallService.acknowledge(guardian, id));
    }

    @DeleteMapping("/api/falls/{id}/")
    public ResponseEntity<Void> delete(@AuthenticationPrincipal Guardian guardian,
                                       @PathVariable Long id) {
        fallService.delete(guardian, id);
        return ResponseEntity.noContent().build();   // 204 — 방 삭제와 같은 모양
    }
}
