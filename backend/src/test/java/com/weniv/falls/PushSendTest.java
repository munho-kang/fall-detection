// 발송 경로 테스트 (키 설정 상태) — 만료 구독 삭제·실패 무해화·vapid-key 200
// pytest의 settings 변경 등가는 클래스 단위 @TestPropertySource다 (503 케이스는 PushSendDisabledTest)
package com.weniv.falls;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import com.jayway.jsonpath.JsonPath;
import com.weniv.falls.domain.PushDevice;
import com.weniv.falls.service.PushService;
import com.weniv.falls.service.WebPushClient;

@TestPropertySource(properties = {
    // pytest TEST_VAPID_KEY와 동일한 32바이트 스칼라(base64url)
    "push.vapid.private-key=AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE",
    "push.vapid.subject=mailto:test@example.com"
})
class PushSendTest extends IntegrationTestBase {

    @MockitoBean
    WebPushClient webPushClient;   // 실제 발송(외부 HTTP)만 목으로 막는다

    @Autowired
    PushService pushService;

    @Test
    void webpush_dead_subscription_deleted() throws Exception {
        PushDevice device = pushDeviceRepository.save(
            new PushDevice(guardian, "webpush", "{\"endpoint\": \"e\"}"));
        when(webPushClient.send(any(), any())).thenReturn(410);   // 만료 구독
        pushService.sendToGuardian(makeEvent(guardian));
        assertThat(pushDeviceRepository.findById(device.getId())).isEmpty();
    }

    @Test
    void send_failure_never_raises() throws Exception {
        pushDeviceRepository.save(new PushDevice(guardian, "webpush", "{\"endpoint\": \"e\"}"));
        when(webPushClient.send(any(), any())).thenThrow(new RuntimeException("boom"));
        // 예외가 새어나오면 테스트 실패 — best-effort 원칙
        assertThatCode(() -> pushService.sendToGuardian(makeEvent(guardian)))
            .doesNotThrowAnyException();
    }

    @Test
    void vapid_key_endpoint_returns_public_key() throws Exception {
        String body = mockMvc.perform(authed(get("/api/push/vapid-key/"), guardian))
            .andExpect(status().isOk())
            .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        String key = JsonPath.read(body, "$.key");
        assertThat(key.length()).isGreaterThan(40);   // base64url 공개키(65바이트 비압축 점)
    }
}
