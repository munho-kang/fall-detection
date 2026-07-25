// 프로필 엔드포인트 — GET·PUT 모두 {"elder_phone"} 하나를 주고받는다
package com.weniv.falls.controller;

import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import com.weniv.falls.domain.Guardian;
import com.weniv.falls.dto.ProfileDto;
import com.weniv.falls.service.ProfileService;

@RestController
public class ProfileController {

    private final ProfileService profileService;

    public ProfileController(ProfileService profileService) {
        this.profileService = profileService;
    }

    @GetMapping("/api/profile/")
    public ProfileDto get(@AuthenticationPrincipal Guardian guardian) {
        return profileService.get(guardian);
    }

    @PutMapping("/api/profile/")
    public ProfileDto put(@AuthenticationPrincipal Guardian guardian,
                          @Valid @RequestBody ProfileDto request) {
        return profileService.update(guardian, request);
    }
}
