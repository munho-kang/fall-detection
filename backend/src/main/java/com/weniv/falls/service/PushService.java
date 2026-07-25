// 낙상 웹 푸시 발송 — best-effort: 어떤 예외도 API 응답에 영향을 주지 않는다 (앱 폴링이 안전망)
// Jackson 3(Boot 4.1) 확인: 컨테이너 ObjectMapper 빈은 tools.jackson.databind.ObjectMapper다
package com.weniv.falls.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

import com.fasterxml.jackson.annotation.JsonProperty;
import tools.jackson.databind.ObjectMapper;

import com.weniv.falls.domain.FallEvent;
import com.weniv.falls.domain.PushDevice;
import com.weniv.falls.repository.PushDeviceRepository;

@Service
public class PushService {

    private static final Logger log = LoggerFactory.getLogger(PushService.class);

    private final PushDeviceRepository pushDeviceRepository;
    private final VapidService vapidService;
    private final WebPushClient webPushClient;
    private final ObjectMapper objectMapper;

    public PushService(PushDeviceRepository pushDeviceRepository, VapidService vapidService,
                       WebPushClient webPushClient, ObjectMapper objectMapper) {
        this.pushDeviceRepository = pushDeviceRepository;
        this.vapidService = vapidService;
        this.webPushClient = webPushClient;
        this.objectMapper = objectMapper;
    }

    // POST 응답이 외부 HTTP를 기다리지 않도록 스레드풀에서 발송한다 (Django 데몬 스레드 등가)
    @Async("pushExecutor")
    public void sendToGuardianAsync(FallEvent event) {
        sendToGuardian(event);
    }

    public void sendToGuardian(FallEvent event) {
        try {
            if (!vapidService.isConfigured()) return;   // 키 미설정 — 조용히 비활성
            // LAZY 프록시라도 getId()는 초기화 없이 안전하다 (비동기 스레드에는 세션이 없다)
            Long guardianId = event.getGuardian().getId();
            for (PushDevice device : pushDeviceRepository.findByGuardianId(guardianId)) {
                sendOne(device, event);
            }
        } catch (Exception e) {
            log.error("푸시 발송 중 예상 밖 오류 (event={})", event.getId(), e);
        }
    }

    private void sendOne(PushDevice device, FallEvent event) {
        try {
            int status = webPushClient.send(device.getToken(), payloadJson(event));
            if (status == 404 || status == 410) {
                pushDeviceRepository.delete(device);   // 만료된 구독은 그 자리에서 정리한다
            } else if (status >= 400) {
                log.error("웹 푸시 발송 실패 (device={}, status={})", device.getId(), status);
            }
        } catch (Exception e) {
            log.error("웹 푸시 발송 실패 (device={})", device.getId(), e);
        }
    }

    // web/sw.js가 파싱하는 형태 — 키 이름·구성이 기존 계약이다
    private String payloadJson(FallEvent event) throws Exception {
        return objectMapper.writeValueAsString(new Payload(
            "fall", event.getId(), event.getRoomName(), event.getRoomNumber(),
            event.getOccurredAt().toString(), event.getConfidence()));
    }

    private record Payload(
        String type,
        Long id,
        @JsonProperty("room_name") String roomName,
        @JsonProperty("room_number") Integer roomNumber,
        @JsonProperty("occurred_at") String occurredAt,
        Double confidence) {
    }
}
