// 프로필 계약 테스트 — 접근 시 get-or-create, PUT 왕복
package com.weniv.falls;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;

class ProfileApiTest extends IntegrationTestBase {

    @Test
    void profile_get_creates_empty() throws Exception {
        mockMvc.perform(authed(get("/api/profile/"), guardian))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.length()").value(1))   // 응답 필드는 elder_phone 하나뿐
            .andExpect(jsonPath("$.elder_phone").value(""));
        assertThat(guardianProfileRepository.findByGuardianId(guardian.getId())).isPresent();
    }

    @Test
    void profile_put_roundtrip() throws Exception {
        mockMvc.perform(authed(put("/api/profile/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"elder_phone\": \"01012345678\"}"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.elder_phone").value("01012345678"));

        mockMvc.perform(authed(get("/api/profile/"), guardian))
            .andExpect(jsonPath("$.elder_phone").value("01012345678"));
    }
}
