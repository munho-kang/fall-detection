// 낙상 등록 요청 — occurred_at은 오프셋 입력을 받기 위해 OffsetDateTime (저장은 UTC Instant)
package com.weniv.falls.dto;

import java.time.OffsetDateTime;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

// body의 guardian 등 잉여 필드는 무시한다 — 요청자로 강제되므로 클라이언트가 건드릴 수 없다
@JsonIgnoreProperties(ignoreUnknown = true)
public record FallEventRequest(
    @JsonProperty("room_name")
    @NotBlank(message = "이 필드는 필수 항목입니다.")
    @Size(max = 20, message = "이 필드의 글자 수가 20 이하인지 확인하십시오.")
    String roomName,

    @JsonProperty("room_number")
    @NotNull(message = "이 필드는 필수 항목입니다.")
    @Min(value = 0, message = "이 값이 0보다 크거나 같은지 확인하십시오.")
    @Max(value = 32767, message = "이 값이 32767보다 작거나 같은지 확인하십시오.")
    Integer roomNumber,

    @JsonProperty("occurred_at")
    @NotNull(message = "이 필드는 필수 항목입니다.")
    OffsetDateTime occurredAt,

    @NotNull(message = "이 필드는 필수 항목입니다.")
    Double confidence,

    @JsonProperty("reported_119_at")
    OffsetDateTime reported119At) {
}
