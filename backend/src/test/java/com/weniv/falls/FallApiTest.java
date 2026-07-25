// 낙상 API 계약 테스트 — 목록 격리·최신순·guardian 강제·acknowledge 멱등·중복 POST 200·푸시 1회/0회
package com.weniv.falls;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.clearInvocations;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import com.jayway.jsonpath.JsonPath;
import com.weniv.falls.domain.FallEvent;
import com.weniv.falls.service.PushService;

class FallApiTest extends IntegrationTestBase {

    @MockitoBean
    PushService pushService;   // pytest의 send_to_guardian_async 목 등가 — 발송 호출 여부만 검증

    private String fallPayload(String confidence) {
        return "{\"room_name\": \"안방\", \"room_number\": 1, "
            + "\"occurred_at\": \"2026-07-23T03:00:00Z\", \"confidence\": " + confidence + "}";
    }

    @Test
    void list_excludes_other_users_events() throws Exception {
        makeEvent(other);
        FallEvent mine = makeEvent(guardian);
        mockMvc.perform(authed(get("/api/falls/"), guardian))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.length()").value(1))
            .andExpect(jsonPath("$[0].id").value(mine.getId()));
    }

    @Test
    void list_is_newest_first() throws Exception {
        FallEvent first = makeEvent(guardian, "안방", 1);
        FallEvent second = makeEvent(guardian, "안방", 2);
        mockMvc.perform(authed(get("/api/falls/"), guardian))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$[0].id").value(second.getId()))
            .andExpect(jsonPath("$[1].id").value(first.getId()));
    }

    @Test
    void post_forces_guardian_to_requester() throws Exception {
        // 클라이언트가 body에 남의 guardian id를 실어도 무시되어야 한다
        String body = mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"room_name\": \"부엌\", \"room_number\": 2, "
                    + "\"occurred_at\": \"2026-07-23T03:00:00Z\", \"confidence\": 0.88, "
                    + "\"guardian\": " + other.getId() + "}"))
            .andExpect(status().isCreated())
            .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        long id = ((Number) JsonPath.read(body, "$.id")).longValue();
        assertThat(fallEventRepository.findById(id).orElseThrow().getGuardian().getId())
            .isEqualTo(guardian.getId());
    }

    @Test
    void acknowledge_other_users_event_404() throws Exception {
        FallEvent theirs = makeEvent(other);
        mockMvc.perform(authed(post("/api/falls/" + theirs.getId() + "/acknowledge/"), guardian))
            .andExpect(status().isNotFound());
    }

    @Test
    void acknowledge_is_idempotent() throws Exception {
        FallEvent event = makeEvent(guardian);
        String url = "/api/falls/" + event.getId() + "/acknowledge/";

        String first = JsonPath.read(
            mockMvc.perform(authed(post(url), guardian))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8),
            "$.acknowledged_at");
        assertThat(first).isNotNull();

        String second = JsonPath.read(
            mockMvc.perform(authed(post(url), guardian))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8),
            "$.acknowledged_at");
        assertThat(second).isEqualTo(first);   // 두 번째 호출이 시각을 덮어쓰면 안 된다
    }

    @Test
    void duplicate_post_returns_200_and_no_new_row() throws Exception {
        String body = mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON).content(fallPayload("0.9")))
            .andExpect(status().isCreated())
            // 직렬화 계약 — UTC ISO-8601 Z 표기 왕복 확인
            .andExpect(jsonPath("$.occurred_at").value("2026-07-23T03:00:00Z"))
            .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        int firstId = JsonPath.read(body, "$.id");

        mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON).content(fallPayload("0.5")))
            .andExpect(status().isOk())               // 중복은 에러가 아니라 200 정상 경로다
            .andExpect(jsonPath("$.id").value(firstId))
            .andExpect(jsonPath("$.confidence").value(0.9));   // 기존 행이 그대로여야 한다
        assertThat(fallEventRepository.count()).isEqualTo(1);
    }

    @Test
    void created_post_sends_push_once() throws Exception {
        String body = mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON).content(fallPayload("0.9")))
            .andExpect(status().isCreated())
            .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        long id = ((Number) JsonPath.read(body, "$.id")).longValue();

        ArgumentCaptor<FallEvent> captor = ArgumentCaptor.forClass(FallEvent.class);
        verify(pushService, times(1)).sendToGuardianAsync(captor.capture());
        assertThat(captor.getValue().getId()).isEqualTo(id);
    }

    @Test
    void duplicate_post_sends_no_push() throws Exception {
        mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON).content(fallPayload("0.9")))
            .andExpect(status().isCreated());
        clearInvocations(pushService);

        mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON).content(fallPayload("0.9")))
            .andExpect(status().isOk());
        verify(pushService, never()).sendToGuardianAsync(any());
    }

    @Test
    void post_accepts_offset_and_stores_utc() throws Exception {
        // 스펙 5절 — 입력은 +09:00 오프셋도 받아 UTC로 변환 저장한다
        mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"room_name\": \"안방\", \"room_number\": 1, "
                    + "\"occurred_at\": \"2026-07-23T12:00:00+09:00\", \"confidence\": 0.9}"))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.occurred_at").value("2026-07-23T03:00:00Z"));
    }
}
