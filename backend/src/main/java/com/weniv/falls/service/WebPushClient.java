// 웹 푸시 발송 어댑터 경계 — 테스트는 이 인터페이스를 목으로 바꿔 외부 HTTP를 차단한다
package com.weniv.falls.service;

public interface WebPushClient {

    /** 구독 JSON으로 페이로드를 발송하고 푸시 서비스의 HTTP 상태 코드를 돌려준다. */
    int send(String subscriptionJson, String payload) throws Exception;
}
