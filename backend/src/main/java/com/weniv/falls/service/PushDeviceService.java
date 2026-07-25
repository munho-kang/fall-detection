// 푸시 기기 등록·해제 — update_or_create 등가(토큰 계정 이전), 해제는 소유자 것만 지운다
package com.weniv.falls.service;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.weniv.falls.domain.Guardian;
import com.weniv.falls.domain.PushDevice;
import com.weniv.falls.repository.PushDeviceRepository;

@Service
public class PushDeviceService {

    private final PushDeviceRepository pushDeviceRepository;

    public PushDeviceService(PushDeviceRepository pushDeviceRepository) {
        this.pushDeviceRepository = pushDeviceRepository;
    }

    @Transactional   // 조회한 엔티티의 필드 변경(dirty checking)까지 한 트랜잭션
    public void register(Guardian guardian, String kind, String token) {
        pushDeviceRepository.findByToken(token).ifPresentOrElse(
            device -> device.reassign(guardian, kind),   // 다른 계정에 있으면 현 사용자로 이전
            () -> pushDeviceRepository.save(new PushDevice(guardian, kind, token)));
    }

    @Transactional   // 파생 delete 쿼리는 트랜잭션이 필요하다
    public void unregister(Guardian guardian, String token) {
        // guardian 조건 포함 — 남의 기기는 지워지지 않지만 응답은 어차피 204다
        pushDeviceRepository.deleteByGuardianIdAndToken(guardian.getId(), token == null ? "" : token);
    }
}
