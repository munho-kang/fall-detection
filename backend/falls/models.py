# 낙상 이벤트·방·프로필·푸시 기기 모델

from django.conf import settings
from django.db import models


class FallEvent(models.Model):
    guardian = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="fall_events"
    )
    room_name = models.CharField(max_length=20)
    room_number = models.PositiveSmallIntegerField()
    occurred_at = models.DateTimeField()  # 클라이언트가 판정한 낙상 시각 (FALLING 진입 시각)
    created_at = models.DateTimeField(auto_now_add=True)
    confidence = models.FloatField()  # 판정 시점 랜드마크 4개의 visibility 평균
    acknowledged_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-id"]  # 목록 API가 최신순이어야 한다
        constraints = [
            # 오프라인 큐 재전송 멱등성의 근거 — 같은 낙상은 두 행이 될 수 없다
            models.UniqueConstraint(
                fields=["guardian", "room_name", "room_number", "occurred_at"],
                name="uniq_fall_dedup",
            )
        ]

    def __str__(self):
        return f"{self.room_name}{self.room_number} {self.occurred_at:%Y-%m-%d %H:%M:%S}"


class Room(models.Model):
    guardian = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="rooms"
    )
    name = models.CharField(max_length=20)
    number = models.PositiveSmallIntegerField()

    class Meta:
        ordering = ["name", "number"]
        constraints = [
            models.UniqueConstraint(
                fields=["guardian", "name", "number"], name="uniq_room_per_guardian"
            )
        ]

    def __str__(self):
        return f"{self.name} {self.number}"


class GuardianProfile(models.Model):
    # "어르신께 전화" 번호의 서버 저장소. 접근 시 get_or_create로 만든다.
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="guardian_profile"
    )
    elder_phone = models.CharField(max_length=20, blank=True, default="")

    def __str__(self):
        return f"{self.user.username} profile"


class PushDevice(models.Model):
    KIND_CHOICES = [("webpush", "webpush")]

    guardian = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="push_devices"
    )
    kind = models.CharField(max_length=10, choices=KIND_CHOICES)
    # Web Push 구독 JSON 문자열
    token = models.TextField(unique=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.guardian.username} {self.kind}"
