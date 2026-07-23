# 낙상 이벤트 등록·조회·확인 API 뷰와 회원가입

from django.db import IntegrityError
from django.utils import timezone
from rest_framework import generics, status
from rest_framework.authtoken.models import Token
from rest_framework.decorators import api_view, permission_classes
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response

from .models import FallEvent, Room
from .serializers import FallEventSerializer, RoomSerializer, SignupSerializer


@api_view(["POST"])
@permission_classes([AllowAny])
def signup(request):
    # 가입 즉시 토큰을 돌려줘 클라이언트가 로그인 요청을 한 번 더 보낼 필요가 없다
    serializer = SignupSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    user = serializer.save()
    token, _ = Token.objects.get_or_create(user=user)
    return Response({"token": token.key}, status=status.HTTP_201_CREATED)


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


class RoomListCreate(generics.ListCreateAPIView):
    serializer_class = RoomSerializer

    def get_queryset(self):
        return Room.objects.filter(guardian=self.request.user)

    def perform_create(self, serializer):
        try:
            serializer.save(guardian=self.request.user)
        except IntegrityError:
            raise ValidationError("같은 이름과 번호의 방이 이미 있습니다.")


class RoomDetail(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = RoomSerializer

    def get_queryset(self):
        # 남의 방은 존재 자체가 드러나지 않고 404가 된다
        return Room.objects.filter(guardian=self.request.user)

    def perform_update(self, serializer):
        try:
            serializer.save()
        except IntegrityError:
            raise ValidationError("같은 이름과 번호의 방이 이미 있습니다.")
