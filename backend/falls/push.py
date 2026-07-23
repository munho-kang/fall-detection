# 낙상 이벤트를 FCM·웹 푸시로 발송하는 모듈 — 키 미설정 채널은 조용히 비활성
#
# 푸시는 best-effort다. 여기서 무슨 일이 나도 API 응답에 영향을 주면 안 되므로
# send_to_guardian은 예외를 절대 밖으로 내보내지 않는다 (앱 폴링이 안전망).

import json
import logging
import threading

from django.conf import settings

logger = logging.getLogger(__name__)

_firebase_lock = threading.Lock()
_firebase_ready = False


def _ensure_firebase():
    """FIREBASE_SERVICE_ACCOUNT가 있으면 firebase_admin을 1회 초기화한다. 미설정이면 False."""
    global _firebase_ready
    if _firebase_ready:
        return True
    if not settings.FIREBASE_SERVICE_ACCOUNT:
        return False
    with _firebase_lock:
        if not _firebase_ready:
            import firebase_admin
            from firebase_admin import credentials

            cred = credentials.Certificate(json.loads(settings.FIREBASE_SERVICE_ACCOUNT))
            firebase_admin.initialize_app(cred)
            _firebase_ready = True
    return True


def vapid_public_key():
    """VAPID 개인키에서 브라우저 구독용 공개키(base64url)를 파생한다. 미설정이면 None."""
    if not settings.VAPID_PRIVATE_KEY:
        return None
    from cryptography.hazmat.primitives import serialization
    from py_vapid import Vapid, b64urlencode

    v = Vapid.from_string(private_key=settings.VAPID_PRIVATE_KEY)
    return b64urlencode(
        v.public_key.public_bytes(
            serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint
        )
    )


def _payload(event):
    return {
        "type": "fall",
        "id": event.id,
        "room_name": event.room_name,
        "room_number": event.room_number,
        "occurred_at": event.occurred_at.isoformat(),
        "confidence": event.confidence,
    }


def _send_fcm(device, event):
    from firebase_admin import messaging

    try:
        messaging.send(
            messaging.Message(
                token=device.token,
                # notification부는 백그라운드에서 OS가 자동 표시한다
                notification=messaging.Notification(
                    title="낙상 감지",
                    body=f"{event.room_name} {event.room_number}에서 낙상 감지",
                ),
                # data부는 포그라운드 onMessage에서 로컬 알림을 만들 때 쓴다 (값은 전부 문자열이어야 한다)
                data={k: str(v) for k, v in _payload(event).items()},
                android=messaging.AndroidConfig(priority="high"),
            )
        )
    except messaging.UnregisteredError:
        device.delete()  # 앱 삭제 등으로 죽은 토큰은 그 자리에서 정리한다
    except Exception:
        logger.exception("FCM 발송 실패 (device=%s)", device.pk)


def _send_webpush(device, event):
    from pywebpush import WebPushException, webpush

    try:
        webpush(
            subscription_info=json.loads(device.token),
            data=json.dumps(_payload(event)),
            vapid_private_key=settings.VAPID_PRIVATE_KEY,
            vapid_claims={"sub": settings.VAPID_SUBJECT},
        )
    except WebPushException as exc:
        if exc.response is not None and exc.response.status_code in (404, 410):
            device.delete()  # 만료된 구독은 그 자리에서 정리한다
        else:
            logger.exception("웹 푸시 발송 실패 (device=%s)", device.pk)
    except Exception:
        logger.exception("웹 푸시 발송 실패 (device=%s)", device.pk)


def send_to_guardian(event):
    """보호자의 모든 기기로 발송한다. 어떤 실패도 밖으로 새어나가지 않는다."""
    try:
        from .models import PushDevice

        for device in PushDevice.objects.filter(guardian=event.guardian):
            if device.kind == "fcm":
                if _ensure_firebase():
                    _send_fcm(device, event)
            elif settings.VAPID_PRIVATE_KEY:
                _send_webpush(device, event)
    except Exception:
        logger.exception("푸시 발송 중 예상 밖 오류 (event=%s)", event.pk)


def send_to_guardian_async(event):
    """POST 응답이 외부 HTTP를 기다리지 않도록 데몬 스레드에서 발송한다."""
    threading.Thread(target=send_to_guardian, args=(event,), daemon=True).start()
