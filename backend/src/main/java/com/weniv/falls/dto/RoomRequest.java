// 방 생성·수정 요청 — PATCH 부분 수정 때문에 필드가 nullable이고 검증은 RoomService가 한다
package com.weniv.falls.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

@JsonIgnoreProperties(ignoreUnknown = true)
public record RoomRequest(String name, Integer number) {
}
