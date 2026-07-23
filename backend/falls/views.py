# 낙상 이벤트 등록·조회·확인 API 뷰와 회원가입

from django.db import IntegrityError
from django.utils import timezone
from rest_framework import generics, status
from rest_framework.authtoken.models import Token
from rest_framework.decorators import api_view, permission_classes
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response

from .models import FallEvent, GuardianProfile, PushDevice, Room
from .serializers import (
    DUPLICATE_ROOM_MESSAGE,
    FallEventSerializer,
    GuardianProfileSerializer,
    PushDeviceSerializer,
    RoomSerializer,
    SignupSerializer,
)


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
            raise ValidationError({"non_field_errors": [DUPLICATE_ROOM_MESSAGE]})


class RoomDetail(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = RoomSerializer

    def get_queryset(self):
        # 남의 방은 존재 자체가 드러나지 않고 404가 된다
        return Room.objects.filter(guardian=self.request.user)

    def perform_update(self, serializer):
        try:
            serializer.save()
        except IntegrityError:
            raise ValidationError({"non_field_errors": [DUPLICATE_ROOM_MESSAGE]})


@api_view(["GET", "PUT"])
@permission_classes([IsAuthenticated])
def profile(request):
    prof, _ = GuardianProfile.objects.get_or_create(user=request.user)
    if request.method == "PUT":
        serializer = GuardianProfileSerializer(prof, data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)
    return Response(GuardianProfileSerializer(prof).data)


@api_view(["POST", "DELETE"])
@permission_classes([IsAuthenticated])
def push_devices(request):
    if request.method == "DELETE":
        # 없는 토큰이어도 204 — 로그아웃 흐름을 막을 이유가 없다
        PushDevice.objects.filter(
            guardian=request.user, token=request.data.get("token", "")
        ).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

    serializer = PushDeviceSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    # 토큰이 다른 계정에 등록돼 있으면 현 사용자로 이전한다 (계정 전환 케이스)
    PushDevice.objects.update_or_create(
        token=serializer.validated_data["token"],
        defaults={"guardian": request.user, "kind": serializer.validated_data["kind"]},
    )
    return Response(status=status.HTTP_201_CREATED)
