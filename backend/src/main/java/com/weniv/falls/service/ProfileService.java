// 보호자 프로필 — 접근 시 get-or-create (Django GuardianProfile.objects.get_or_create 등가)
package com.weniv.falls.service;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;

import com.weniv.falls.domain.Guardian;
import com.weniv.falls.domain.GuardianProfile;
import com.weniv.falls.dto.ProfileDto;
import com.weniv.falls.repository.GuardianProfileRepository;

@Service
public class ProfileService {

    private final GuardianProfileRepository profileRepository;

    public ProfileService(GuardianProfileRepository profileRepository) {
        this.profileRepository = profileRepository;
    }

    public ProfileDto get(Guardian guardian) {
        return ProfileDto.from(getOrCreate(guardian));
    }

    public ProfileDto update(Guardian guardian, ProfileDto request) {
        GuardianProfile profile = getOrCreate(guardian);
        // Django와 동일 — 필드가 아예 없으면(null) 기존 값을 유지한다 (클라이언트는 항상 보낸다)
        if (request.elderPhone() != null) {
            profile.updatePhone(request.elderPhone());
            profileRepository.save(profile);
        }
        return ProfileDto.from(profile);
    }

    private GuardianProfile getOrCreate(Guardian guardian) {
        return profileRepository.findByGuardianId(guardian.getId()).orElseGet(() -> {
            try {
                return profileRepository.saveAndFlush(new GuardianProfile(guardian));
            } catch (DataIntegrityViolationException e) {
                // get_or_create 경합 — 동시에 만들어졌으면 그 행을 쓴다
                return profileRepository.findByGuardianId(guardian.getId()).orElseThrow();
            }
        });
    }
}
