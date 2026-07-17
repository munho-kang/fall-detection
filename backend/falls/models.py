# 낙상 이벤트 1건을 저장하는 유일한 모델 (방 정보를 이벤트에 직접 들고 있다)

from django.conf import settings
from django.db import models


class FallEvent(models.Model):
    ROOM_CHOICES = [("안방", "안방"), ("부엌", "부엌"), ("거실", "거실"), ("화장실", "화장실")]

    guardian = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="fall_events"
    )
    room_name = models.CharField(max_length=20, choices=ROOM_CHOICES)
    room_number = models.PositiveSmallIntegerField()
    occurred_at = models.DateTimeField()  # 클라이언트가 판정한 낙상 시각 (FALLING 진입 시각)
    created_at = models.DateTimeField(auto_now_add=True)
    confidence = models.FloatField()  # 판정 시점 랜드마크 4개의 visibility 평균
    acknowledged_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-id"]  # 목록 API가 최신순이어야 한다

    def __str__(self):
        return f"{self.room_name}{self.room_number} {self.occurred_at:%Y-%m-%d %H:%M:%S}"
