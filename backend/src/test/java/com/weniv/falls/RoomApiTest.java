// 방 CRUD 계약 테스트 — 소유권 격리·중복 400(문자열 고정)·경합 안전망
package com.weniv.falls;

import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doReturn;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;

import com.jayway.jsonpath.JsonPath;
import com.weniv.falls.domain.Room;
import com.weniv.falls.repository.RoomRepository;

class RoomApiTest extends IntegrationTestBase {

    // 베이스의 roomRepository와 같은 빈 — 경합 테스트에서 사전 검사만 골라 무력화한다
    @MockitoSpyBean
    RoomRepository roomRepositorySpy;

    @Test
    void room_crud_roundtrip() throws Exception {
        String body = mockMvc.perform(authed(post("/api/rooms/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\": \"안방\", \"number\": 1}"))
            .andExpect(status().isCreated())
            .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        int roomId = JsonPath.read(body, "$.id");

        mockMvc.perform(authed(get("/api/rooms/"), guardian))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.length()").value(1))
            .andExpect(jsonPath("$[0].name").value("안방"));

        mockMvc.perform(authed(patch("/api/rooms/" + roomId + "/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\": \"서재\"}"))   // 웹은 name만 보낸다 — 부분 수정
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.name").value("서재"));

        mockMvc.perform(authed(delete("/api/rooms/" + roomId + "/"), guardian))
            .andExpect(status().isNoContent());

        mockMvc.perform(authed(get("/api/rooms/"), guardian))
            .andExpect(jsonPath("$.length()").value(0));
    }

    @Test
    void room_list_excludes_other_users() throws Exception {
        roomRepository.save(new Room(other, "부엌", 1));
        mockMvc.perform(authed(get("/api/rooms/"), guardian))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.length()").value(0));
    }

    @Test
    void room_patch_other_users_404() throws Exception {
        Room theirs = roomRepository.save(new Room(other, "부엌", 1));
        mockMvc.perform(authed(patch("/api/rooms/" + theirs.getId() + "/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\": \"x\"}"))
            .andExpect(status().isNotFound());
    }

    @Test
    void room_duplicate_create_400() throws Exception {
        roomRepository.save(new Room(guardian, "안방", 1));
        mockMvc.perform(authed(post("/api/rooms/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\": \"안방\", \"number\": 1}"))
            .andExpect(status().isBadRequest());
    }

    @Test
    void room_duplicate_race_returns_400() throws Exception {
        // 사전 검사를 우회해 경합 시 안전망(DataIntegrityViolationException → 400)을 직접 검증한다
        roomRepository.save(new Room(guardian, "안방", 1));
        doReturn(false).when(roomRepositorySpy)
            .existsByGuardianIdAndNameAndNumber(anyLong(), anyString(), anyInt());
        mockMvc.perform(authed(post("/api/rooms/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\": \"안방\", \"number\": 1}"))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.non_field_errors.length()").value(1))
            .andExpect(jsonPath("$.non_field_errors[0]").value("같은 이름과 번호의 방이 이미 있습니다."));
    }
}
