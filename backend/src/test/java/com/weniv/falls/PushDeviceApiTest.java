// 푸시 기기 등록·해제 계약 테스트 — 계정 이전·항상 204 해제·kind 검증
package com.weniv.falls;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;

import com.weniv.falls.domain.PushDevice;

class PushDeviceApiTest extends IntegrationTestBase {

    @Test
    void push_device_register() throws Exception {
        mockMvc.perform(authed(post("/api/push/devices/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"kind\": \"webpush\", \"token\": \"tok-1\"}"))
            .andExpect(status().isCreated());
        PushDevice device = pushDeviceRepository.findByToken("tok-1").orElseThrow();
        assertThat(device.getGuardian().getId()).isEqualTo(guardian.getId());
        assertThat(device.getKind()).isEqualTo("webpush");
    }

    @Test
    void push_device_token_moves_to_current_user() throws Exception {
        // 같은 브라우저에서 계정을 전환한 경우 — 토큰은 마지막 사용자 것이 된다
        mockMvc.perform(authed(post("/api/push/devices/"), other)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"kind\": \"webpush\", \"token\": \"tok-1\"}"))
            .andExpect(status().isCreated());
        mockMvc.perform(authed(post("/api/push/devices/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"kind\": \"webpush\", \"token\": \"tok-1\"}"))
            .andExpect(status().isCreated());
        assertThat(pushDeviceRepository.count()).isEqualTo(1);
        assertThat(pushDeviceRepository.findByToken("tok-1").orElseThrow().getGuardian().getId())
            .isEqualTo(guardian.getId());
    }

    @Test
    void push_device_delete() throws Exception {
        pushDeviceRepository.save(new PushDevice(guardian, "webpush", "tok-1"));
        mockMvc.perform(authed(delete("/api/push/devices/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"token\": \"tok-1\"}"))   // 비표준 DELETE body — 기존 계약
            .andExpect(status().isNoContent());
        assertThat(pushDeviceRepository.count()).isEqualTo(0);
    }

    @Test
    void push_device_bad_kind_400() throws Exception {
        // fcm은 Android 지원 제거로 더 이상 유효하지 않다
        for (String kind : new String[] {"smoke-signal", "fcm"}) {
            mockMvc.perform(authed(post("/api/push/devices/"), guardian)
                    .contentType(MediaType.APPLICATION_JSON)
                    .content("{\"kind\": \"" + kind + "\", \"token\": \"t\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.kind").isArray());
        }
    }
}
