// 발송 경로 테스트 (키 미설정 상태) — 발송 전체 스킵·vapid-key 503(문자열 고정)
package com.weniv.falls;

import static org.mockito.Mockito.verifyNoInteractions;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import com.weniv.falls.domain.PushDevice;
import com.weniv.falls.service.PushService;
import com.weniv.falls.service.WebPushClient;

@TestPropertySource(properties = {"push.vapid.private-key=", "push.vapid.subject="})
class PushSendDisabledTest extends IntegrationTestBase {

    @MockitoBean
    WebPushClient webPushClient;

    @Autowired
    PushService pushService;

    @Test
    void send_skips_when_vapid_unset() {
        pushDeviceRepository.save(new PushDevice(guardian, "webpush", "{\"endpoint\": \"e\"}"));
        pushService.sendToGuardian(makeEvent(guardian));
        verifyNoInteractions(webPushClient);   // 키가 없으면 발송 시도 자체가 없어야 한다
    }

    @Test
    void vapid_key_endpoint_503_when_unset() throws Exception {
        mockMvc.perform(authed(get("/api/push/vapid-key/"), guardian))
            .andExpect(status().isServiceUnavailable())
            .andExpect(jsonPath("$.detail").value("웹 푸시가 설정되지 않았습니다."));   // 문자열 고정
    }
}
