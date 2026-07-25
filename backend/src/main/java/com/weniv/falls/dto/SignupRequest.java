// 가입 요청 — 검증 규칙이 조건부(Django 등가)라 AuthService가 직접 검증한다
package com.weniv.falls.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

@JsonIgnoreProperties(ignoreUnknown = true)
public record SignupRequest(String username, String password) {
}
