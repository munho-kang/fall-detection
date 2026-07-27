// 낙상 API 계약 테스트 — 목록 격리·최신순·guardian 강제·acknowledge 멱등·중복 POST 200·신고 병합·푸시 1회/0회·삭제 204/400/404
package com.weniv.falls;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.clearInvocations;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import com.jayway.jsonpath.JsonPath;
import com.weniv.falls.domain.FallEvent;
import com.weniv.falls.service.FallService;
import com.weniv.falls.service.PushService;

class FallApiTest extends IntegrationTestBase {

    @MockitoBean
    PushService pushService;   // pytest의 send_to_guardian_async 목 등가 — 발송 호출 여부만 검증

    private String fallPayload(String confidence) {
        return "{\"room_name\": \"안방\", \"room_number\": 1, "
            + "\"occurred_at\": \"2026-07-23T03:00:00Z\", \"confidence\": " + confidence + "}";
    }

    private String fallPayloadReported(String reportedAt) {
        return "{\"room_name\": \"안방\", \"room_number\": 1, "
            + "\"occurred_at\": \"2026-07-23T03:00:00Z\", \"confidence\": 0.9, "
            + "\"reported_119_at\": \"" + reportedAt + "\"}";
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

    @Test
    void delete_acknowledged_event_204_and_disappears_from_list() throws Exception {
        FallEvent event = makeEvent(guardian);
        mockMvc.perform(authed(post("/api/falls/" + event.getId() + "/acknowledge/"), guardian))
            .andExpect(status().isOk());

        mockMvc.perform(authed(delete("/api/falls/" + event.getId() + "/"), guardian))
            .andExpect(status().isNoContent());

        assertThat(fallEventRepository.findById(event.getId())).isEmpty();
        mockMvc.perform(authed(get("/api/falls/"), guardian))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.length()").value(0));
    }

    @Test
    void delete_unacknowledged_event_400_and_row_kept() throws Exception {
        FallEvent event = makeEvent(guardian);

        mockMvc.perform(authed(delete("/api/falls/" + event.getId() + "/"), guardian))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.non_field_errors[0]")
                .value(FallService.UNACKNOWLEDGED_DELETE_MESSAGE));

        assertThat(fallEventRepository.findById(event.getId())).isPresent();
    }

    @Test
    void delete_other_users_event_is_404_regardless_of_acknowledgement() throws Exception {
        // 확인 여부를 소유권보다 먼저 보면, 남의 미확인 기록에 400이 나가면서
        // "그 id는 존재하고 아직 미확인"이라는 사실이 새어나간다. 둘 다 404여야 한다.
        FallEvent theirsAcked = makeEvent(other, "안방", 1);
        mockMvc.perform(authed(post("/api/falls/" + theirsAcked.getId() + "/acknowledge/"), other))
            .andExpect(status().isOk());
        FallEvent theirsUnacked = makeEvent(other, "부엌", 2);

        mockMvc.perform(authed(delete("/api/falls/" + theirsAcked.getId() + "/"), guardian))
            .andExpect(status().isNotFound());
        mockMvc.perform(authed(delete("/api/falls/" + theirsUnacked.getId() + "/"), guardian))
            .andExpect(status().isNotFound());

        assertThat(fallEventRepository.count()).isEqualTo(2);   // 남의 기록은 하나도 안 지워졌다
    }

    @Test
    void post_with_reported_119_at_creates_row_with_it() throws Exception {
        // 원본이 큐에 갇혔다가 신고분이 먼저 도착하는 드문 경로 — 신고 재-POST가 행을 만든다
        String body = mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content(fallPayloadReported("2026-07-23T03:00:20Z")))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.reported_119_at").value("2026-07-23T03:00:20Z"))
            .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        long id = ((Number) JsonPath.read(body, "$.id")).longValue();
        assertThat(fallEventRepository.findById(id).orElseThrow().getReported119At())
            .isEqualTo(Instant.parse("2026-07-23T03:00:20Z"));
    }

    @Test
    void duplicate_post_merges_reported_119_at_and_sends_no_push() throws Exception {
        // 정상 경로 — 5s 원본 201 뒤에 20s 신고 재-POST가 200으로 병합된다
        String body = mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON).content(fallPayload("0.9")))
            .andExpect(status().isCreated())
            .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        int firstId = JsonPath.read(body, "$.id");
        clearInvocations(pushService);

        mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content(fallPayloadReported("2026-07-23T03:00:20Z")))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.id").value(firstId))
            .andExpect(jsonPath("$.reported_119_at").value("2026-07-23T03:00:20Z"));

        assertThat(fallEventRepository.count()).isEqualTo(1);
        verify(pushService, never()).sendToGuardianAsync(any());   // 200 병합은 푸시가 없다
    }

    @Test
    void reported_119_at_is_immutable_once_set() throws Exception {
        mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content(fallPayloadReported("2026-07-23T03:00:20Z")))
            .andExpect(status().isCreated());

        mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content(fallPayloadReported("2026-07-23T03:00:59Z")))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.reported_119_at").value("2026-07-23T03:00:20Z"));   // 첫 값 보존
    }

    @Test
    void duplicate_post_without_reported_119_at_keeps_existing_value() throws Exception {
        // 오프라인 큐가 신고 이후 원본을 재전송해도 신고 시각이 지워지면 안 된다
        mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content(fallPayloadReported("2026-07-23T03:00:20Z")))
            .andExpect(status().isCreated());

        mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON).content(fallPayload("0.9")))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.reported_119_at").value("2026-07-23T03:00:20Z"));
    }
}
