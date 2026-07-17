# 낙상 이벤트 등록·조회·확인 API 뷰

from django.utils import timezone
from rest_framework import generics, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .models import FallEvent
from .serializers import FallEventSerializer


class FallEventListCreate(generics.ListCreateAPIView):
    serializer_class = FallEventSerializer

    def get_queryset(self):
        # 남의 이벤트가 절대 새어나가지 않도록 요청자로 필터링한다
        return FallEvent.objects.filter(guardian=self.request.user)

    def perform_create(self, serializer):
        serializer.save(guardian=self.request.user)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def acknowledge(request, pk):
    # guardian까지 걸어서 조회하므로 남의 이벤트는 존재 자체가 드러나지 않고 404가 된다
    try:
        event = FallEvent.objects.get(pk=pk, guardian=request.user)
    except FallEvent.DoesNotExist:
        return Response({"detail": "Not found."}, status=status.HTTP_404_NOT_FOUND)

    if event.acknowledged_at is None:  # 첫 확인 시각을 보존한다
        event.acknowledged_at = timezone.now()
        event.save(update_fields=["acknowledged_at"])

    return Response(FallEventSerializer(event).data)
