# FallEvent를 JSON으로 변환하는 시리얼라이저

from rest_framework import serializers

from .models import FallEvent


class FallEventSerializer(serializers.ModelSerializer):
    class Meta:
        model = FallEvent
        fields = [
            "id",
            "room_name",
            "room_number",
            "occurred_at",
            "created_at",
            "confidence",
            "acknowledged_at",
        ]
        # guardian은 필드에 없다. 요청자로 강제되므로 클라이언트가 건드릴 수 없다.
        read_only_fields = ["id", "created_at", "acknowledged_at"]
