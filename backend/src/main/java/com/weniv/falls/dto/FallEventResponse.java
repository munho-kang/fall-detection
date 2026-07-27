// 낙상 응답 — snake_case 고정, 시각은 Instant가 ISO-8601 Z로 직렬화된다
package com.weniv.falls.dto;

import java.time.Instant;
import com.fasterxml.jackson.annotation.JsonProperty;

import com.weniv.falls.domain.FallEvent;

public record FallEventResponse(
    Long id,
    @JsonProperty("room_name") String roomName,
    @JsonProperty("room_number") Integer roomNumber,
    @JsonProperty("occurred_at") Instant occurredAt,
    @JsonProperty("created_at") Instant createdAt,
    Double confidence,
    @JsonProperty("acknowledged_at") Instant acknowledgedAt,
    @JsonProperty("reported_119_at") Instant reported119At,
    @JsonProperty("voice_ok_at") Instant voiceOkAt) {

    public static FallEventResponse from(FallEvent event) {
        return new FallEventResponse(event.getId(), event.getRoomName(), event.getRoomNumber(),
            event.getOccurredAt(), event.getCreatedAt(), event.getConfidence(),
            event.getAcknowledgedAt(), event.getReported119At(), event.getVoiceOkAt());
    }
}
