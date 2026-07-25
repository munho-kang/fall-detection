// nl.martijndwars:web-push 어댑터 — 구독 JSON 파싱과 VAPID 서명 발송
// Jackson 3(Boot 4.1) 확인: 컨테이너 ObjectMapper 빈은 tools.jackson.databind.ObjectMapper다
package com.weniv.falls.service;

import org.springframework.stereotype.Component;

import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

import nl.martijndwars.webpush.Encoding;
import nl.martijndwars.webpush.Notification;
import nl.martijndwars.webpush.Subscription;

@Component
public class MartijnDwarsWebPushClient implements WebPushClient {

    private final VapidService vapidService;
    private final ObjectMapper objectMapper;
    private volatile nl.martijndwars.webpush.PushService delegate;

    public MartijnDwarsWebPushClient(VapidService vapidService, ObjectMapper objectMapper) {
        this.vapidService = vapidService;
        this.objectMapper = objectMapper;
    }

    @Override
    public int send(String subscriptionJson, String payload) throws Exception {
        // 구독 JSON에는 expirationTime 등 잉여 필드가 있어 수동으로 필요한 값만 뽑는다
        JsonNode node = objectMapper.readTree(subscriptionJson);
        Subscription subscription = new Subscription(
            node.get("endpoint").asString(),
            new Subscription.Keys(
                node.at("/keys/p256dh").asString(),
                node.at("/keys/auth").asString()));
        // 명시적으로 AES128GCM(RFC 8291 표준 인코딩 — VAPID는 RFC 8292의 Authorization 헤더로 통합)을 지정한다.
        // 인자 없는 send()는 레거시 AESGCM(별도 Crypto-Key 헤더)로 기본 설정되는데, FCM이
        // 이를 "crypto-key header had invalid format"라며 403으로 거부한다.
        var response = delegate().send(new Notification(subscription, payload), Encoding.AES128GCM);
        return response.getStatusLine().getStatusCode();
    }

    // 키는 기동 후 바뀌지 않으므로 첫 발송 때 한 번만 만든다
    private nl.martijndwars.webpush.PushService delegate() throws Exception {
        if (delegate == null) {
            delegate = new nl.martijndwars.webpush.PushService(
                vapidService.publicKey(), vapidService.privateKey(), vapidService.subject());
        }
        return delegate;
    }
}
