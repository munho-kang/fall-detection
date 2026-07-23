# FallEvent를 JSON으로 변환하는 시리얼라이저

from django.contrib.auth import password_validation
from django.contrib.auth.models import User
from rest_framework import serializers

from .models import FallEvent, GuardianProfile, Room

DUPLICATE_ROOM_MESSAGE = "같은 이름과 번호의 방이 이미 있습니다."


class SignupSerializer(serializers.ModelSerializer):
    # 비밀번호가 응답 JSON에 실리지 않도록 쓰기 전용으로 막는다
    password = serializers.CharField(write_only=True)

    class Meta:
        model = User
        fields = ["username", "password"]

    def validate_password(self, value):
        # settings의 AUTH_PASSWORD_VALIDATORS(8자 미만·흔한 비밀번호·숫자만 금지)를 가입에도 적용한다
        password_validation.validate_password(value)
        return value

    def create(self, validated_data):
        # create_user가 비밀번호를 해시해서 저장한다. 기본 create()면 평문으로 저장되므로 반드시 이쪽.
        return User.objects.create_user(**validated_data)


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


class RoomSerializer(serializers.ModelSerializer):
    class Meta:
        model = Room
        fields = ["id", "name", "number"]

    def validate(self, attrs):
        # DB의 unique 제약을 IntegrityError(500) 대신 400으로 돌려주기 위한 사전 검사
        user = self.context["request"].user
        name = attrs.get("name", getattr(self.instance, "name", None))
        number = attrs.get("number", getattr(self.instance, "number", None))
        dup = Room.objects.filter(guardian=user, name=name, number=number)
        if self.instance is not None:
            dup = dup.exclude(pk=self.instance.pk)
        if dup.exists():
            raise serializers.ValidationError(DUPLICATE_ROOM_MESSAGE)
        return attrs


class GuardianProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = GuardianProfile
        fields = ["elder_phone"]


class PushDeviceSerializer(serializers.Serializer):
    kind = serializers.ChoiceField(choices=["fcm", "webpush"])
    token = serializers.CharField()
