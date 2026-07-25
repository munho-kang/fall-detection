// VAPID 키 관리 — 개인키(base64url 32바이트 스칼라)에서 공개키를 EC 연산으로 파생한다
package com.weniv.falls.service;

import java.math.BigInteger;
import java.security.Security;
import java.util.Base64;
import org.bouncycastle.jce.ECNamedCurveTable;
import org.bouncycastle.jce.provider.BouncyCastleProvider;
import org.bouncycastle.jce.spec.ECNamedCurveParameterSpec;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class VapidService {

    private static final Logger log = LoggerFactory.getLogger(VapidService.class);

    static {
        // web-push 라이브러리와 공개키 파생 둘 다 BC 프로바이더가 필요하다
        if (Security.getProvider(BouncyCastleProvider.PROVIDER_NAME) == null) {
            Security.addProvider(new BouncyCastleProvider());
        }
    }

    private final String privateKey;
    private final String subject;
    private volatile String cachedPublicKey;

    public VapidService(@Value("${push.vapid.private-key:}") String privateKey,
                        @Value("${push.vapid.subject:}") String subject) {
        this.privateKey = privateKey == null ? "" : privateKey.trim();
        this.subject = subject == null ? "" : subject.trim();
    }

    public boolean isConfigured() {
        return !privateKey.isEmpty();
    }

    public String privateKey() { return privateKey; }
    public String subject() { return subject; }

    // P-256 공개키 = G × d (비압축 점 65바이트)를 base64url로. 미설정·파생 실패면 null → 503 경로
    public String publicKey() {
        if (!isConfigured()) return null;
        if (cachedPublicKey != null) return cachedPublicKey;
        try {
            ECNamedCurveParameterSpec spec = ECNamedCurveTable.getParameterSpec("prime256v1");
            BigInteger d = new BigInteger(1, Base64.getUrlDecoder().decode(privateKey));
            byte[] point = spec.getG().multiply(d).normalize().getEncoded(false);
            cachedPublicKey = Base64.getUrlEncoder().withoutPadding().encodeToString(point);
            return cachedPublicKey;
        } catch (Exception e) {
            log.error("VAPID 공개키 파생 실패 — 키 형식을 확인하세요 (base64url 32바이트 스칼라)", e);
            return null;
        }
    }
}
