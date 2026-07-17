# 낙상 이벤트 등록·조회 API 뷰

from rest_framework import generics

from .models import FallEvent
from .serializers import FallEventSerializer


class FallEventListCreate(generics.ListCreateAPIView):
    serializer_class = FallEventSerializer

    def get_queryset(self):
        # 남의 이벤트가 절대 새어나가지 않도록 요청자로 필터링한다
        return FallEvent.objects.filter(guardian=self.request.user)

    def perform_create(self, serializer):
        serializer.save(guardian=self.request.user)
