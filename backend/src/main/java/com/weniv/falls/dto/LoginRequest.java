// 로그인 요청 — 필수 검증은 Bean Validation, 자격 대조는 AuthService
package com.weniv.falls.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.validation.constraints.NotBlank;

@JsonIgnoreProperties(ignoreUnknown = true)
public record LoginRequest(
    @NotBlank(message = "이 필드는 필수 항목입니다.") String username,
    @NotBlank(message = "이 필드는 필수 항목입니다.") String password) {
}
