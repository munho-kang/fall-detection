// 프로필 요청·응답 겸용 — {"elder_phone"} 하나뿐
package com.weniv.falls.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.Size;

import com.weniv.falls.domain.GuardianProfile;

@JsonIgnoreProperties(ignoreUnknown = true)
public record ProfileDto(
    @JsonProperty("elder_phone")
    @Size(max = 20, message = "이 필드의 글자 수가 20 이하인지 확인하십시오.")
    String elderPhone) {

    public static ProfileDto from(GuardianProfile profile) {
        return new ProfileDto(profile.getElderPhone());
    }
}
