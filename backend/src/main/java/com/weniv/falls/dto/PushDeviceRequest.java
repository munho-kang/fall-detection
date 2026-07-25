// 푸시 기기 등록 요청 — kind는 webpush만 유효 (DRF ChoiceField 등가)
package com.weniv.falls.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;

@JsonIgnoreProperties(ignoreUnknown = true)
public record PushDeviceRequest(
    @NotNull(message = "이 필드는 필수 항목입니다.")
    @Pattern(regexp = "webpush", message = "\"webpush\"만 유효한 선택입니다.")
    String kind,
    @NotBlank(message = "이 필드는 필수 항목입니다.")
    String token) {
}
