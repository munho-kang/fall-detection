// 푸시 기기 해제 요청 — DELETE body {"token"} (비표준이지만 기존 계약)
package com.weniv.falls.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

@JsonIgnoreProperties(ignoreUnknown = true)
public record PushDeviceDeleteRequest(String token) {
}
