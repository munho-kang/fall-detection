# 낙상 이벤트를 웹 푸시로 발송하는 모듈 — 키 미설정이면 조용히 비활성
#
# 푸시는 best-effort다. 여기서 무슨 일이 나도 API 응답에 영향을 주면 안 되므로
# send_to_guardian은 예외를 절대 밖으로 내보내지 않는다 (앱 폴링이 안전망).

import json
import logging
import threading

from django.conf import settings

logger = logging.getLogger(__name__)


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

        if not settings.VAPID_PRIVATE_KEY:
            return
        for device in PushDevice.objects.filter(guardian=event.guardian):
            _send_webpush(device, event)
    except Exception:
        logger.exception("푸시 발송 중 예상 밖 오류 (event=%s)", event.pk)


def send_to_guardian_async(event):
    """POST 응답이 외부 HTTP를 기다리지 않도록 데몬 스레드에서 발송한다."""
    threading.Thread(target=send_to_guardian, args=(event,), daemon=True).start()
