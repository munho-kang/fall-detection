// 인증 계약 테스트 — 401 형태·로그인 토큰·가입 즉시 발급·중복/약한 비밀번호 400
package com.weniv.falls;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;

class AuthApiTest extends IntegrationTestBase {

    @Test
    void anonymous_gets_401() throws Exception {
        mockMvc.perform(get("/api/falls/"))
            .andExpect(status().isUnauthorized())
            .andExpect(jsonPath("$.detail").exists());   // {"detail": "..."} 형태 고정
    }

    @Test
    void login_returns_token() throws Exception {
        mockMvc.perform(post("/api/auth/login/").contentType(MediaType.APPLICATION_JSON)
                .content("{\"username\": \"g1\", \"password\": \"pw12345\"}"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.token").isNotEmpty());
    }

    @Test
    void login_wrong_password_400() throws Exception {
        mockMvc.perform(post("/api/auth/login/").contentType(MediaType.APPLICATION_JSON)
                .content("{\"username\": \"g1\", \"password\": \"wrong-pass\"}"))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.non_field_errors").isArray());
    }

    // Task 7에서 "그 토큰으로 GET /api/falls/ 200" 검증이 추가된다 (엔드포인트가 그때 생긴다)
    @Test
    void signup_returns_token_and_logs_in() throws Exception {
        mockMvc.perform(post("/api/auth/signup/").contentType(MediaType.APPLICATION_JSON)
                .content("{\"username\": \"new1\", \"password\": \"tough-pass-9x\"}"))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.token").isNotEmpty());
    }

    @Test
    void signup_duplicate_username_400() throws Exception {
        // g1은 베이스 픽스처로 이미 존재한다
        mockMvc.perform(post("/api/auth/signup/").contentType(MediaType.APPLICATION_JSON)
                .content("{\"username\": \"g1\", \"password\": \"tough-pass-9x\"}"))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.username").isArray());
    }

    @Test
    void signup_weak_password_400() throws Exception {
        // 8자 미만·전부 숫자·흔한 비밀번호 — 셋 다 걸리는 입력
        mockMvc.perform(post("/api/auth/signup/").contentType(MediaType.APPLICATION_JSON)
                .content("{\"username\": \"new2\", \"password\": \"1234\"}"))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.password").isArray());
    }
}
