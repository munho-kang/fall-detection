// 통합 테스트 공통 베이스 — 실 Postgres(fall_detection_test)에 매 테스트 전 TRUNCATE로 초기화
package com.weniv.falls;

import java.time.Instant;
import org.junit.jupiter.api.BeforeEach;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import com.weniv.falls.domain.AuthToken;
import com.weniv.falls.domain.FallEvent;
import com.weniv.falls.domain.Guardian;
import com.weniv.falls.repository.AuthTokenRepository;
import com.weniv.falls.repository.FallEventRepository;
import com.weniv.falls.repository.GuardianProfileRepository;
import com.weniv.falls.repository.GuardianRepository;
import com.weniv.falls.repository.PushDeviceRepository;
import com.weniv.falls.repository.RoomRepository;

@SpringBootTest
@AutoConfigureMockMvc
public abstract class IntegrationTestBase {

    @Autowired protected MockMvc mockMvc;
    @Autowired protected JdbcTemplate jdbcTemplate;
    @Autowired protected GuardianRepository guardianRepository;
    @Autowired protected AuthTokenRepository authTokenRepository;
    @Autowired protected FallEventRepository fallEventRepository;
    @Autowired protected RoomRepository roomRepository;
    @Autowired protected GuardianProfileRepository guardianProfileRepository;
    @Autowired protected PushDeviceRepository pushDeviceRepository;
    @Autowired protected PasswordEncoder passwordEncoder;

    protected Guardian guardian;   // pytest fixture guardian(g1) 등가
    protected Guardian other;      // pytest fixture other(g2) 등가

    @BeforeEach
    void resetDatabase() {
        jdbcTemplate.execute(
            "TRUNCATE TABLE push_device, guardian_profile, room, fall_event, auth_token, guardian "
                + "RESTART IDENTITY CASCADE");
        guardian = createGuardian("g1");
        other = createGuardian("g2");
    }

    protected Guardian createGuardian(String username) {
        return guardianRepository.save(new Guardian(username, passwordEncoder.encode("pw12345")));
    }

    protected String tokenFor(Guardian g) {
        return authTokenRepository.findByGuardianId(g.getId())
            .orElseGet(() -> authTokenRepository.save(new AuthToken(AuthToken.newKey(), g)))
            .getKey();
    }

    protected FallEvent makeEvent(Guardian g) {
        return makeEvent(g, "안방", 1);
    }

    protected FallEvent makeEvent(Guardian g, String roomName, int roomNumber) {
        return fallEventRepository.save(new FallEvent(g, roomName, roomNumber, Instant.now(), 0.9));
    }

    // client_for(user) 등가 — 요청에 Token 헤더를 붙인다
    protected MockHttpServletRequestBuilder authed(MockHttpServletRequestBuilder builder, Guardian g) {
        return builder.header("Authorization", "Token " + tokenFor(g));
    }
}
