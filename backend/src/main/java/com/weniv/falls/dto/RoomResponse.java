// 방 응답 — {"id", "name", "number"}
package com.weniv.falls.dto;

import com.weniv.falls.domain.Room;

public record RoomResponse(Long id, String name, Integer number) {

    public static RoomResponse from(Room room) {
        return new RoomResponse(room.getId(), room.getName(), room.getNumber());
    }
}
