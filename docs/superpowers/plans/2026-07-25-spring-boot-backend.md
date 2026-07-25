# 백엔드 Spring Boot 교체 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Django 백엔드를 Java 21 + Spring Boot(4.x) + PostgreSQL로 완전 교체하되, 웹·Flutter 클라이언트가 한 줄도 안 바뀌고 그대로 동작하게 한다.

**Architecture:** 표준 레이어드(controller/service/repository/domain) + Spring Security 커스텀 토큰 필터(DRF TokenAuthentication 등가) + Flyway `V1__init.sql`(유니크 제약 이름 SQL 고정) + `@Async` best-effort 웹 푸시. 기존 pytest 32개를 JUnit 5 + MockMvc로 1:1 포팅한 테스트가 계약 검수 수단이다.

**Tech Stack:** Java 21(Temurin, 설치 확인됨) · Spring Boot 스캐폴딩 시점 최신 안정판(start.spring.io 기본값, 현재 4.1.0) · Gradle Groovy DSL + 래퍼 · Spring Data JPA · Flyway · PostgreSQL 18(Homebrew 서비스 실행 중, 확인됨) · `nl.martijndwars:web-push:5.1.2` + `org.bouncycastle:bcprov-jdk18on:1.80` · JUnit 5 + MockMvc.

**스펙:** `docs/superpowers/specs/2026-07-24-spring-boot-backend-design.md`

## Global Constraints

스펙의 전 태스크 공통 요구다. 모든 태스크의 요구사항에 이 절이 암묵적으로 포함된다.

- **클라이언트 무수정** — `web/`, `app/`은 어떤 이유로도 수정 금지. 진단이 필요하면 서버 쪽을 고친다.
- **API 계약 고정** — 경로 끝 슬래시(`/api/falls/`), 상태 코드, snake_case 필드, `Authorization: Token <key>` 헤더, 에러 형태(`{필드: [메시지…]}` / `{"detail": "..."}`)까지 기존과 동일.
- **문자열까지 고정된 응답 2개** — 방 중복 400 `{"non_field_errors": ["같은 이름과 번호의 방이 이미 있습니다."]}`, VAPID 미설정 503 `{"detail": "웹 푸시가 설정되지 않았습니다."}`.
- **서버** — 포트 `8000`, 바인딩 `0.0.0.0`, CORS 전 오리진 허용, CSRF 비활성, 세션 STATELESS.
- **DB** — 운영 `fall_detection`, 테스트 `fall_detection_test`(둘 다 로컬 Postgres). 시각은 전부 UTC `timestamptz`. 유니크 제약 이름 `uniq_fall_dedup`, `uniq_room_per_guardian`은 Flyway SQL에서 지정.
- **직렬화** — 시각 출력은 UTC ISO-8601 `Z` 표기(소수 초 허용), 입력은 `+09:00` 오프셋도 수용해 UTC 변환 저장. `room_number`·`number`는 0~32767.
- **인증 예외 경로** — `permitAll`은 `/`, `/api/auth/login/`, `/api/auth/signup/` 셋뿐.
- **에러 메시지 언어** — 검증 메시지는 한국어(위 2개 외 문구 자체는 자유, 형태 고정).
- **새 Java 파일 규칙** — 첫 줄(패키지 선언 위)에 한국어 한 줄 주석으로 파일 역할 기재.
- **커밋** — 의미 단위, 형식 `type: 한국어 요약 — 부연`. 메시지 끝에 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- **Django 코드는 Task 9까지 보존** — Task 3이 Django venv 안의 파일(공통 비밀번호 목록)을 소스로 쓰므로 그 전에 지우면 안 된다.

## 파일 구조 (최종)

```
backend/
  build.gradle, settings.gradle, gradlew, gradle/          # start.spring.io 스캐폴딩
  src/main/java/com/weniv/falls/
    FallsApplication.java
    controller/  HealthController, AuthController, RoomController,
                 ProfileController, PushController, FallController
    service/     AuthService, RoomService, ProfileService, PushDeviceService,
                 VapidService, WebPushClient(인터페이스), MartijnDwarsWebPushClient,
                 PushService, FallService
    repository/  GuardianRepository, AuthTokenRepository, FallEventRepository,
                 RoomRepository, GuardianProfileRepository, PushDeviceRepository
    domain/      Guardian, AuthToken, FallEvent, Room, GuardianProfile, PushDevice
    dto/         LoginRequest, SignupRequest, TokenResponse, FallEventRequest,
                 FallEventResponse, RoomRequest, RoomResponse, ProfileDto,
                 PushDeviceRequest, PushDeviceDeleteRequest, VapidKeyResponse
    config/      SecurityConfig, TokenAuthFilter, CorsConfig, AsyncConfig
    error/       GlobalExceptionHandler, FieldValidationException, NotFoundException
  src/main/resources/
    application.yml
    common-passwords.txt                                   # Django 목록 상위 500개
    db/migration/V1__init.sql
  src/test/resources/application.yml                       # fall_detection_test 접속
  src/test/java/com/weniv/falls/
    IntegrationTestBase.java   HealthApiTest   DomainConstraintTest   AuthApiTest
    RoomApiTest   ProfileApiTest   PushDeviceApiTest   PushSendTest
    PushSendDisabledTest   FallApiTest
```

스펙 3절의 service 목록에 `VapidService`·`WebPushClient`(+구현체)·`PushDeviceService`를 추가했다. 발송 경로를 목으로 막는 포팅 테스트(스펙 9절 "발송은 목으로 막는다")가 성립하려면 외부 HTTP를 치는 부분이 별도 빈이어야 하기 때문이다.

## 테스트 대응표 — pytest 32개 → JUnit 36개

vapid 200/503은 Spring에서 프로퍼티가 컨텍스트 단위라 두 클래스로 갈라 33개가 되고, 스펙 5절 계약 행 검증용 신규 3개(헬스체크·로그인 실패 400·오프셋 입력)를 더해 총 36개다.

| pytest | JUnit (클래스.메서드) | Task |
|---|---|---|
| test_anonymous_gets_401 | AuthApiTest.anonymous_gets_401 | 3 |
| test_login_returns_token | AuthApiTest.login_returns_token | 3 |
| test_list_excludes_other_users_events | FallApiTest.list_excludes_other_users_events | 7 |
| test_list_is_newest_first | FallApiTest.list_is_newest_first | 7 |
| test_post_forces_guardian_to_requester | FallApiTest.post_forces_guardian_to_requester | 7 |
| test_acknowledge_other_users_event_404 | FallApiTest.acknowledge_other_users_event_404 | 7 |
| test_acknowledge_is_idempotent | FallApiTest.acknowledge_is_idempotent | 7 |
| test_signup_returns_token_and_logs_in | AuthApiTest.signup_returns_token_and_logs_in (Task 7에서 falls GET 검증 추가) | 3·7 |
| test_signup_duplicate_username_400 | AuthApiTest.signup_duplicate_username_400 | 3 |
| test_signup_weak_password_400 | AuthApiTest.signup_weak_password_400 | 3 |
| test_fall_event_room_name_is_free_text | DomainConstraintTest.fall_event_room_name_is_free_text | 2 |
| test_fall_event_rejects_exact_duplicate | DomainConstraintTest.fall_event_rejects_exact_duplicate | 2 |
| test_room_unique_per_guardian | DomainConstraintTest.room_unique_per_guardian | 2 |
| test_same_room_allowed_for_other_guardian | DomainConstraintTest.same_room_allowed_for_other_guardian | 2 |
| test_room_crud_roundtrip | RoomApiTest.room_crud_roundtrip | 4 |
| test_room_list_excludes_other_users | RoomApiTest.room_list_excludes_other_users | 4 |
| test_room_patch_other_users_404 | RoomApiTest.room_patch_other_users_404 | 4 |
| test_room_duplicate_create_400 | RoomApiTest.room_duplicate_create_400 | 4 |
| test_room_duplicate_race_returns_400 | RoomApiTest.room_duplicate_race_returns_400 | 4 |
| test_profile_get_creates_empty | ProfileApiTest.profile_get_creates_empty | 4 |
| test_profile_put_roundtrip | ProfileApiTest.profile_put_roundtrip | 4 |
| test_push_device_register | PushDeviceApiTest.push_device_register | 5 |
| test_push_device_token_moves_to_current_user | PushDeviceApiTest.push_device_token_moves_to_current_user | 5 |
| test_push_device_delete | PushDeviceApiTest.push_device_delete | 5 |
| test_push_device_bad_kind_400 | PushDeviceApiTest.push_device_bad_kind_400 | 5 |
| test_send_skips_when_vapid_unset | PushSendDisabledTest.send_skips_when_vapid_unset | 6 |
| test_webpush_dead_subscription_deleted | PushSendTest.webpush_dead_subscription_deleted | 6 |
| test_send_failure_never_raises | PushSendTest.send_failure_never_raises | 6 |
| test_vapid_key_endpoint | PushSendTest.vapid_key_endpoint_returns_public_key + PushSendDisabledTest.vapid_key_endpoint_503_when_unset | 6 |
| test_duplicate_post_returns_200_and_no_new_row | FallApiTest.duplicate_post_returns_200_and_no_new_row | 7 |
| test_created_post_sends_push_once | FallApiTest.created_post_sends_push_once | 7 |
| test_duplicate_post_sends_no_push | FallApiTest.duplicate_post_sends_no_push | 7 |
| (신규) | HealthApiTest.root_healthcheck | 1 |
| (신규) | AuthApiTest.login_wrong_password_400 | 3 |
| (신규) | FallApiTest.post_accepts_offset_and_stores_utc | 7 |

---

### Task 1: Spring Boot 스캐폴딩 + 헬스체크

Django와 같은 `backend/` 디렉터리에 Spring 프로젝트를 공존시킨다(파일 충돌 없음 — Django는 `manage.py`·`config/`·`falls/`, Spring은 `build.gradle`·`src/`). Django 삭제는 Task 9다.

**Files:**
- Create: `backend/build.gradle`, `backend/settings.gradle`, `backend/gradlew`, `backend/gradle/` (스캐폴딩 산출물)
- Create: `backend/src/main/java/com/weniv/falls/FallsApplication.java` (스캐폴딩 산출물, 헤더 주석 추가)
- Create: `backend/src/main/resources/application.yml`
- Create: `backend/src/main/resources/db/migration/.gitkeep`
- Create: `backend/src/test/resources/application.yml`
- Create: `backend/src/main/java/com/weniv/falls/controller/HealthController.java`
- Create: `backend/src/main/java/com/weniv/falls/config/SecurityConfig.java` (초기판 — Task 3에서 확장)
- Create: `backend/src/main/java/com/weniv/falls/config/CorsConfig.java`
- Test: `backend/src/test/java/com/weniv/falls/HealthApiTest.java`
- Delete: 스캐폴딩이 만든 `backend/HELP.md`, `backend/src/main/resources/application.properties`, `backend/src/test/java/com/weniv/falls/FallsApplicationTests.java`

**Interfaces:**
- Consumes: 없음 (첫 태스크)
- Produces: `SecurityConfig`의 `PasswordEncoder` 빈(BCrypt — Task 2 테스트 베이스가 사용), JSON 401 엔트리포인트, `permitAll("/")`. 이후 모든 태스크의 빌드·테스트 기반.

- [ ] **Step 1: DB 생성 (최초 1회, 멱등)**

```bash
createdb fall_detection 2>/dev/null; createdb fall_detection_test 2>/dev/null
psql -lqt | cut -d'|' -f1 | grep -E "fall_detection(_test)?"
```

Expected: 두 DB 이름이 출력된다. (postgresql@18 Homebrew 서비스는 이미 실행 중 — `psql -l` 동작 확인됨.)

- [ ] **Step 2: start.spring.io 스캐폴딩을 backend/에 전개**

```bash
cd /Users/munhokang/82107/weniv_project
curl -s https://start.spring.io/starter.tgz \
  -d type=gradle-project -d language=java -d javaVersion=21 -d packaging=jar \
  -d groupId=com.weniv -d artifactId=falls -d name=falls \
  -d packageName=com.weniv.falls \
  -d dependencies=web,security,data-jpa,postgresql,flyway,validation \
  | tar -xz -C backend
rm backend/HELP.md
rm backend/src/test/java/com/weniv/falls/FallsApplicationTests.java   # HealthApiTest가 컨텍스트 기동을 대신 검증
ls backend
```

Expected: `build.gradle settings.gradle gradlew gradle src .gitignore`가 기존 Django 파일들과 나란히 생긴다. `bootVersion`은 지정하지 않는다(스펙: 스캐폴딩 시점 최신 안정판) — `build.gradle`의 실제 버전을 확인해 context-notes.md에 기록한다. `build.gradle` dependencies에 최소한 `spring-boot-starter-security`(또는 4.x 명칭), web(mvc)·data-jpa·validation 스타터, `flyway-core`+`flyway-database-postgresql`, `org.postgresql:postgresql`, `spring-boot-starter-test`, `spring-security-test`가 있는지 눈으로 확인한다.

**Jackson 세대 확인:** Boot 4.x는 Jackson 3(`tools.jackson`)일 수 있다. `./gradlew dependencies --configuration runtimeClasspath | grep -i jackson`으로 확인하고 context-notes.md에 기록한다. 이 계획의 코드는 어노테이션(`com.fasterxml.jackson.annotation.*` — Jackson 3에서도 패키지 유지)만 쓰도록 작성했고, `ObjectMapper` 직접 주입은 PushService·MartijnDwarsWebPushClient(Task 6) 두 곳뿐이다. 그 두 곳의 import만 확인된 세대에 맞춘다.

- [ ] **Step 3: application.properties를 yml 두 벌로 교체**

`backend/src/main/resources/application.yml` (새 파일):

```yaml
server:
  port: 8000
  address: 0.0.0.0    # 같은 와이파이 기기의 접속을 받는다

spring:
  datasource:
    url: jdbc:postgresql://127.0.0.1:5432/fall_detection
    username: ${USER}    # Homebrew Postgres — 로컬 macOS 사용자, 비밀번호 없음
    password: ""
  jpa:
    hibernate:
      ddl-auto: none     # 스키마는 Flyway가 소유한다
    open-in-view: false

push:
  vapid:
    private-key: ${VAPID_PRIVATE_KEY:}   # 미설정이면 푸시 조용히 비활성 (스펙 7절)
    subject: ${VAPID_SUBJECT:}
```

`backend/src/test/resources/application.yml` (새 파일 — 테스트에선 이 파일이 main yml을 통째로 대체하므로 전체를 다시 쓴다):

```yaml
server:
  port: 8000

spring:
  datasource:
    url: jdbc:postgresql://127.0.0.1:5432/fall_detection_test
    username: ${USER}
    password: ""
  jpa:
    hibernate:
      ddl-auto: none
    open-in-view: false

push:
  vapid:
    private-key: ""    # 셸에 VAPID 환경변수가 있어도 테스트에 새지 않게 고정
    subject: ""
```

빈 마이그레이션 디렉터리로 Flyway가 기동하도록 `backend/src/main/resources/db/migration/.gitkeep`(빈 파일)을 만든다(V1은 Task 2). `backend/src/main/resources/application.properties`는 삭제.

- [ ] **Step 4: FallsApplication에 헤더 주석 추가**

`backend/src/main/java/com/weniv/falls/FallsApplication.java` 첫 줄(패키지 선언 위)에:

```java
// 낙상 감지 백엔드 진입점 — Spring Boot 애플리케이션
```

- [ ] **Step 5: 실패하는 헬스체크 테스트 작성**

`backend/src/test/java/com/weniv/falls/HealthApiTest.java` (새 파일 — DB 픽스처가 필요 없어 Task 2의 IntegrationTestBase를 상속하지 않는 유일한 테스트):

```java
// 루트 헬스체크 계약 테스트 — 기존 Django 응답 JSON과 동일해야 한다
package com.weniv.falls;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
class HealthApiTest {

    @Autowired
    MockMvc mockMvc;

    @Test
    void root_healthcheck() throws Exception {
        mockMvc.perform(get("/"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value("ok"))
            .andExpect(jsonPath("$.service").value("fall-detection-backend"));
    }
}
```

- [ ] **Step 6: 테스트 실패 확인**

Run: `cd backend && ./gradlew test --tests "com.weniv.falls.HealthApiTest"`
Expected: FAIL — Security 스타터 기본값이 모든 요청을 잠그므로 401 (컨트롤러도 아직 없다).

- [ ] **Step 7: HealthController + 초기 SecurityConfig + CorsConfig 구현**

`backend/src/main/java/com/weniv/falls/controller/HealthController.java` (새 파일):

```java
// 루트 헬스체크 — 서버 생존 확인용 JSON (기존 Django 응답과 동일)
package com.weniv.falls.controller;

import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HealthController {

    @GetMapping("/")
    public Map<String, String> health() {
        return Map.of("status", "ok", "service", "fall-detection-backend");
    }
}
```

`backend/src/main/java/com/weniv/falls/config/SecurityConfig.java` (새 파일 — Task 3에서 토큰 필터와 auth 경로 permitAll이 추가된다):

```java
// API 보안 설정 — 세션 없는 토큰 인증, CSRF 비활성, 401은 DRF 형태 JSON
package com.weniv.falls.config;

import java.io.IOException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .csrf(csrf -> csrf.disable())
            .cors(Customizer.withDefaults())
            .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .httpBasic(b -> b.disable())
            .formLogin(f -> f.disable())
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/").permitAll()
                .anyRequest().authenticated())
            .exceptionHandling(e -> e.authenticationEntryPoint(SecurityConfig::unauthorized));
        return http.build();
    }

    // DRF와 같은 {"detail": "..."} 형태 — 클라이언트는 상태 코드만 보므로 문구는 자유다
    private static void unauthorized(HttpServletRequest request, HttpServletResponse response,
                                     AuthenticationException ex) throws IOException {
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        response.setContentType("application/json;charset=UTF-8");
        response.getWriter().write("{\"detail\": \"인증 자격 증명이 제공되지 않았습니다.\"}");
    }

    @Bean
    PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}
```

`backend/src/main/java/com/weniv/falls/config/CorsConfig.java` (새 파일):

```java
// CORS 전 오리진 허용 — 같은 와이파이의 기기가 http://<Mac IP>:5500 등 임의 오리진으로 접속한다
package com.weniv.falls.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

@Configuration
public class CorsConfig {

    @Bean
    CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration config = new CorsConfiguration();
        config.addAllowedOriginPattern("*");   // 토큰 헤더 인증이라 credentials가 없어 * 허용이 안전하다
        config.addAllowedMethod("*");
        config.addAllowedHeader("*");
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", config);
        return source;
    }
}
```

- [ ] **Step 8: 테스트 통과 확인**

Run: `cd backend && ./gradlew test`
Expected: BUILD SUCCESSFUL (HealthApiTest 1개 통과 — 컨텍스트 기동이 test DB 연결·Flyway 빈 기동까지 검증한다).

- [ ] **Step 9: bootRun 스모크 (운영 DB 연결 확인)**

백그라운드로 `cd backend && ./gradlew bootRun`을 띄우고 기동을 기다린 뒤:

```bash
curl -s http://127.0.0.1:8000/
```

Expected: `{"status":"ok","service":"fall-detection-backend"}` (키 순서 무관). 확인 후 bootRun 프로세스를 종료한다.

- [ ] **Step 10: 커밋**

```bash
cd /Users/munhokang/82107/weniv_project
git add backend/build.gradle backend/settings.gradle backend/gradlew backend/gradlew.bat \
  backend/gradle backend/.gitignore backend/src
git commit -m "chore: Spring Boot 스캐폴딩 — :8000 헬스체크·PostgreSQL 연결·보안 기본형

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

주의: `git add backend`(디렉터리 통째)는 금지 — Django 파일과 `.DS_Store`가 섞인다. 위 명시 경로만 추가한다. `web/showcase.html`(기존 untracked)은 건드리지 않는다.

---

### Task 2: 도메인 6종 + Flyway V1 + 리포지토리

Django 모델의 1:1 이식(스펙 4절). 유니크 제약 이름은 SQL로 결정적으로 지정한다. 테스트 공통 베이스(실 Postgres, 매 테스트 전 TRUNCATE)도 여기서 만든다 — pytest의 `transaction=True`와 같은 "실제 커밋" 의미론이라, 제약 위반·경합 안전망 테스트가 트랜잭션 롤백 상태 오염 없이 동작한다.

**Files:**
- Create: `backend/src/main/resources/db/migration/V1__init.sql`
- Delete: `backend/src/main/resources/db/migration/.gitkeep` (V1이 생겼으니 용도 종료)
- Create: `backend/src/main/java/com/weniv/falls/domain/Guardian.java`, `AuthToken.java`, `FallEvent.java`, `Room.java`, `GuardianProfile.java`, `PushDevice.java`
- Create: `backend/src/main/java/com/weniv/falls/repository/GuardianRepository.java`, `AuthTokenRepository.java`, `FallEventRepository.java`, `RoomRepository.java`, `GuardianProfileRepository.java`, `PushDeviceRepository.java`
- Create: `backend/src/test/java/com/weniv/falls/IntegrationTestBase.java`
- Test: `backend/src/test/java/com/weniv/falls/DomainConstraintTest.java`

**Interfaces:**
- Consumes: `PasswordEncoder` 빈 (Task 1 SecurityConfig)
- Produces (이후 태스크 전부가 사용):
  - 엔티티 생성자 — `new Guardian(String username, String bcryptHash)`, `new AuthToken(String key, Guardian g)`, `new FallEvent(Guardian g, String roomName, Integer roomNumber, Instant occurredAt, Double confidence)`, `new Room(Guardian g, String name, Integer number)`, `new GuardianProfile(Guardian g)`(elder_phone "" 초기값), `new PushDevice(Guardian g, String kind, String token)`
  - 도메인 메서드 — `AuthToken.newKey()`(static, 40자 hex), `FallEvent.acknowledgeNow()`(첫 호출만 시각 기록), `Room.rename(String name, Integer number)`, `GuardianProfile.updatePhone(String)`, `PushDevice.reassign(Guardian g, String kind)`
  - 게터 — 모든 필드 `getXxx()` (`FallEvent.getId/getGuardian/getRoomName/getRoomNumber/getOccurredAt/getCreatedAt/getConfidence/getAcknowledgedAt` 등)
  - 리포지토리 시그니처 — 아래 Step 3 코드가 정본
  - `IntegrationTestBase` — `protected Guardian guardian`("g1"), `other`("g2"), `mockMvc`, 각 리포지토리, `createGuardian(String)`, `tokenFor(Guardian)`, `makeEvent(Guardian)`, `makeEvent(Guardian, String, int)`, `authed(MockHttpServletRequestBuilder, Guardian)`

- [ ] **Step 1: Flyway V1 작성**

`backend/src/main/resources/db/migration/V1__init.sql` (새 파일). `.gitkeep`은 삭제한다.

```sql
-- 낙상 감지 백엔드 초기 스키마 — Django 모델 1:1 이식, 유니크 제약 이름을 여기서 고정한다
CREATE TABLE guardian (
    id         BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    username   VARCHAR(150) NOT NULL,
    password   VARCHAR(100) NOT NULL,          -- BCrypt 해시
    created_at TIMESTAMPTZ  NOT NULL,
    CONSTRAINT uniq_guardian_username UNIQUE (username)
);

-- DRF authtoken 등가 — 보호자당 1개, 만료 없음
CREATE TABLE auth_token (
    key         VARCHAR(40) PRIMARY KEY,        -- 40자 hex 랜덤
    guardian_id BIGINT      NOT NULL REFERENCES guardian (id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL,
    CONSTRAINT uniq_auth_token_guardian UNIQUE (guardian_id)
);

CREATE TABLE fall_event (
    id              BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    guardian_id     BIGINT           NOT NULL REFERENCES guardian (id) ON DELETE CASCADE,
    room_name       VARCHAR(20)      NOT NULL,  -- 방 문자열 스냅샷 (Room FK 아님 — 방을 지워도 기록 보존)
    room_number     SMALLINT         NOT NULL,
    occurred_at     TIMESTAMPTZ      NOT NULL,
    created_at      TIMESTAMPTZ      NOT NULL,
    confidence      DOUBLE PRECISION NOT NULL,
    acknowledged_at TIMESTAMPTZ,
    -- 오프라인 큐 재전송 멱등성의 근거 — 같은 낙상은 두 행이 될 수 없다
    CONSTRAINT uniq_fall_dedup UNIQUE (guardian_id, room_name, room_number, occurred_at)
);

CREATE TABLE room (
    id          BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    guardian_id BIGINT      NOT NULL REFERENCES guardian (id) ON DELETE CASCADE,
    name        VARCHAR(20) NOT NULL,
    number      SMALLINT    NOT NULL,
    CONSTRAINT uniq_room_per_guardian UNIQUE (guardian_id, name, number)
);

CREATE TABLE guardian_profile (
    id          BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    guardian_id BIGINT      NOT NULL REFERENCES guardian (id) ON DELETE CASCADE,
    elder_phone VARCHAR(20) NOT NULL DEFAULT '',
    CONSTRAINT uniq_guardian_profile_guardian UNIQUE (guardian_id)
);

CREATE TABLE push_device (
    id          BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    guardian_id BIGINT      NOT NULL REFERENCES guardian (id) ON DELETE CASCADE,
    kind        VARCHAR(10) NOT NULL,           -- "webpush"만 유효 (검증은 API 계층)
    token       TEXT        NOT NULL,           -- Web Push 구독 JSON 문자열
    created_at  TIMESTAMPTZ NOT NULL,
    CONSTRAINT uniq_push_device_token UNIQUE (token)
);
```

- [ ] **Step 2: 실패하는 제약 테스트 + 테스트 베이스 작성**

`backend/src/test/java/com/weniv/falls/IntegrationTestBase.java` (새 파일):

```java
// 통합 테스트 공통 베이스 — 실 Postgres(fall_detection_test)에 매 테스트 전 TRUNCATE로 초기화
// pytest의 transaction=True와 같은 실제-커밋 의미론이라 제약 위반·경합 테스트가 안전하다
package com.weniv.falls;

import java.time.Instant;
import org.junit.jupiter.api.BeforeEach;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import com.weniv.falls.domain.AuthToken;
import com.weniv.falls.domain.FallEvent;
import com.weniv.falls.domain.Guardian;
import com.weniv.falls.repository.AuthTokenRepository;
import com.weniv.falls.repository.FallEventRepository;
import com.weniv.falls.repository.GuardianProfileRepository;
import com.weniv.falls.repository.GuardianRepository;
import com.weniv.falls.repository.PushDeviceRepository;
import com.weniv.falls.repository.RoomRepository;

@SpringBootTest
@AutoConfigureMockMvc
public abstract class IntegrationTestBase {

    @Autowired protected MockMvc mockMvc;
    @Autowired protected JdbcTemplate jdbcTemplate;
    @Autowired protected GuardianRepository guardianRepository;
    @Autowired protected AuthTokenRepository authTokenRepository;
    @Autowired protected FallEventRepository fallEventRepository;
    @Autowired protected RoomRepository roomRepository;
    @Autowired protected GuardianProfileRepository guardianProfileRepository;
    @Autowired protected PushDeviceRepository pushDeviceRepository;
    @Autowired protected PasswordEncoder passwordEncoder;

    protected Guardian guardian;   // pytest fixture guardian(g1) 등가
    protected Guardian other;      // pytest fixture other(g2) 등가

    @BeforeEach
    void resetDatabase() {
        jdbcTemplate.execute(
            "TRUNCATE TABLE push_device, guardian_profile, room, fall_event, auth_token, guardian "
                + "RESTART IDENTITY CASCADE");
        guardian = createGuardian("g1");
        other = createGuardian("g2");
    }

    protected Guardian createGuardian(String username) {
        return guardianRepository.save(new Guardian(username, passwordEncoder.encode("pw12345")));
    }

    protected String tokenFor(Guardian g) {
        return authTokenRepository.findByGuardianId(g.getId())
            .orElseGet(() -> authTokenRepository.save(new AuthToken(AuthToken.newKey(), g)))
            .getKey();
    }

    protected FallEvent makeEvent(Guardian g) {
        return makeEvent(g, "안방", 1);
    }

    protected FallEvent makeEvent(Guardian g, String roomName, int roomNumber) {
        return fallEventRepository.save(new FallEvent(g, roomName, roomNumber, Instant.now(), 0.9));
    }

    // client_for(user) 등가 — 요청에 Token 헤더를 붙인다
    protected MockHttpServletRequestBuilder authed(MockHttpServletRequestBuilder builder, Guardian g) {
        return builder.header("Authorization", "Token " + tokenFor(g));
    }
}
```

`backend/src/test/java/com/weniv/falls/DomainConstraintTest.java` (새 파일):

```java
// 데이터 모델 제약 테스트 — 낙상 중복 금지·방 보호자별 유니크 (pytest Task 1 구획 포팅)
package com.weniv.falls;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Instant;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;

import com.weniv.falls.domain.FallEvent;
import com.weniv.falls.domain.Room;

class DomainConstraintTest extends IntegrationTestBase {

    @Test
    void fall_event_room_name_is_free_text() {
        // 고정 선택지(choices) 없이 임의 문자열 방 이름이 그대로 저장돼야 한다
        FallEvent e = makeEvent(guardian, "서재", 1);
        assertThat(fallEventRepository.findById(e.getId()).orElseThrow().getRoomName())
            .isEqualTo("서재");
    }

    @Test
    void fall_event_rejects_exact_duplicate() {
        Instant t = Instant.now();
        fallEventRepository.saveAndFlush(new FallEvent(guardian, "안방", 1, t, 0.9));
        assertThatThrownBy(() ->
            fallEventRepository.saveAndFlush(new FallEvent(guardian, "안방", 1, t, 0.8)))
            .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void room_unique_per_guardian() {
        roomRepository.saveAndFlush(new Room(guardian, "안방", 1));
        assertThatThrownBy(() -> roomRepository.saveAndFlush(new Room(guardian, "안방", 1)))
            .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void same_room_allowed_for_other_guardian() {
        roomRepository.saveAndFlush(new Room(guardian, "안방", 1));
        roomRepository.saveAndFlush(new Room(other, "안방", 1));   // 예외 없이 저장돼야 한다
    }
}
```

- [ ] **Step 3: 컴파일 실패 확인**

Run: `cd backend && ./gradlew test --tests "com.weniv.falls.DomainConstraintTest"`
Expected: FAIL — 컴파일 오류 (domain·repository 클래스 미존재).

- [ ] **Step 4: 엔티티 6종 구현**

`backend/src/main/java/com/weniv/falls/domain/Guardian.java` (새 파일):

```java
// 보호자 계정 — Django User의 대체 (username·password만 사용)
package com.weniv.falls.domain;

import java.time.Instant;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

@Entity
@Table(name = "guardian")
public class Guardian {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, length = 150, unique = true)
    private String username;

    @Column(nullable = false, length = 100)
    private String password;   // BCrypt 해시

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected Guardian() {}

    public Guardian(String username, String password) {
        this.username = username;
        this.password = password;
    }

    @PrePersist
    void onCreate() {
        if (createdAt == null) createdAt = Instant.now();
    }

    public Long getId() { return id; }
    public String getUsername() { return username; }
    public String getPassword() { return password; }
}
```

`backend/src/main/java/com/weniv/falls/domain/AuthToken.java` (새 파일):

```java
// DRF authtoken 등가 — 보호자당 1개, 만료 없는 40자 hex 키 ("한 번 로그인하면 유지" 보존)
package com.weniv.falls.domain;

import java.security.SecureRandom;
import java.time.Instant;
import java.util.HexFormat;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.OneToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

@Entity
@Table(name = "auth_token")
public class AuthToken {

    @Id
    @Column(name = "key", length = 40)
    private String key;

    @OneToOne(optional = false)
    @JoinColumn(name = "guardian_id", nullable = false, unique = true)
    private Guardian guardian;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected AuthToken() {}

    public AuthToken(String key, Guardian guardian) {
        this.key = key;
        this.guardian = guardian;
    }

    // DRF Token.generate_key 등가 — os.urandom(20)의 hex 40자
    public static String newKey() {
        byte[] bytes = new byte[20];
        new SecureRandom().nextBytes(bytes);
        return HexFormat.of().formatHex(bytes);
    }

    @PrePersist
    void onCreate() {
        if (createdAt == null) createdAt = Instant.now();
    }

    public String getKey() { return key; }
    public Guardian getGuardian() { return guardian; }
}
```

`backend/src/main/java/com/weniv/falls/domain/FallEvent.java` (새 파일):

```java
// 낙상 이벤트 — 방 정보는 문자열 스냅샷, (guardian, room, number, occurred_at) 유니크가 멱등성 근거
package com.weniv.falls.domain;

import java.time.Instant;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

@Entity
@Table(name = "fall_event")
public class FallEvent {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "guardian_id", nullable = false)
    private Guardian guardian;

    @Column(name = "room_name", nullable = false, length = 20)
    private String roomName;

    @Column(name = "room_number", nullable = false)
    private Integer roomNumber;

    @Column(name = "occurred_at", nullable = false)
    private Instant occurredAt;   // 클라이언트가 판정한 낙상 시각 (FALLING 진입 시각)

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(nullable = false)
    private Double confidence;    // 판정 시점 랜드마크 4개의 visibility 평균

    @Column(name = "acknowledged_at")
    private Instant acknowledgedAt;

    protected FallEvent() {}

    public FallEvent(Guardian guardian, String roomName, Integer roomNumber,
                     Instant occurredAt, Double confidence) {
        this.guardian = guardian;
        this.roomName = roomName;
        this.roomNumber = roomNumber;
        this.occurredAt = occurredAt;
        this.confidence = confidence;
    }

    @PrePersist
    void onCreate() {
        if (createdAt == null) createdAt = Instant.now();
    }

    // 첫 확인 시각을 보존한다 — 두 번째 호출부터는 무시 (멱등)
    // 마이크로초 절단: PG timestamptz 정밀도와 맞춰, 응답 직렬화(메모리 값)와 재조회 값이 항상 같게 한다
    public void acknowledgeNow() {
        if (acknowledgedAt == null) {
            acknowledgedAt = Instant.now().truncatedTo(java.time.temporal.ChronoUnit.MICROS);
        }
    }

    public Long getId() { return id; }
    public Guardian getGuardian() { return guardian; }
    public String getRoomName() { return roomName; }
    public Integer getRoomNumber() { return roomNumber; }
    public Instant getOccurredAt() { return occurredAt; }
    public Instant getCreatedAt() { return createdAt; }
    public Double getConfidence() { return confidence; }
    public Instant getAcknowledgedAt() { return acknowledgedAt; }
}
```

`backend/src/main/java/com/weniv/falls/domain/Room.java` (새 파일):

```java
// 방 — 보호자별 (name, number) 유니크
package com.weniv.falls.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

@Entity
@Table(name = "room")
public class Room {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "guardian_id", nullable = false)
    private Guardian guardian;

    @Column(nullable = false, length = 20)
    private String name;

    @Column(nullable = false)
    private Integer number;

    protected Room() {}

    public Room(Guardian guardian, String name, Integer number) {
        this.guardian = guardian;
        this.name = name;
        this.number = number;
    }

    public void rename(String name, Integer number) {
        this.name = name;
        this.number = number;
    }

    public Long getId() { return id; }
    public Guardian getGuardian() { return guardian; }
    public String getName() { return name; }
    public Integer getNumber() { return number; }
}
```

`backend/src/main/java/com/weniv/falls/domain/GuardianProfile.java` (새 파일):

```java
// 보호자 프로필 — "어르신께 전화" 번호 저장소, 접근 시 get-or-create
package com.weniv.falls.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.OneToOne;
import jakarta.persistence.Table;

@Entity
@Table(name = "guardian_profile")
public class GuardianProfile {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @OneToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "guardian_id", nullable = false, unique = true)
    private Guardian guardian;

    @Column(name = "elder_phone", nullable = false, length = 20)
    private String elderPhone = "";

    protected GuardianProfile() {}

    public GuardianProfile(Guardian guardian) {
        this.guardian = guardian;
    }

    public void updatePhone(String elderPhone) {
        this.elderPhone = elderPhone;
    }

    public Long getId() { return id; }
    public String getElderPhone() { return elderPhone; }
}
```

`backend/src/main/java/com/weniv/falls/domain/PushDevice.java` (새 파일):

```java
// 웹 푸시 구독 기기 — token은 구독 JSON 문자열, 전역 유니크 (계정 전환 시 이전된다)
package com.weniv.falls.domain;

import java.time.Instant;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

@Entity
@Table(name = "push_device")
public class PushDevice {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "guardian_id", nullable = false)
    private Guardian guardian;

    @Column(nullable = false, length = 10)
    private String kind;

    @Column(nullable = false, unique = true, columnDefinition = "text")
    private String token;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected PushDevice() {}

    public PushDevice(Guardian guardian, String kind, String token) {
        this.guardian = guardian;
        this.kind = kind;
        this.token = token;
    }

    // update_or_create 등가 — 같은 토큰이 다른 계정에 있으면 현 사용자로 이전한다
    public void reassign(Guardian guardian, String kind) {
        this.guardian = guardian;
        this.kind = kind;
    }

    @PrePersist
    void onCreate() {
        if (createdAt == null) createdAt = Instant.now();
    }

    public Long getId() { return id; }
    public Guardian getGuardian() { return guardian; }
    public String getKind() { return kind; }
    public String getToken() { return token; }
}
```

- [ ] **Step 5: 리포지토리 6종 구현**

`backend/src/main/java/com/weniv/falls/repository/GuardianRepository.java` (새 파일):

```java
// 보호자 조회 — 로그인·가입 중복 검사용
package com.weniv.falls.repository;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import com.weniv.falls.domain.Guardian;

public interface GuardianRepository extends JpaRepository<Guardian, Long> {
    Optional<Guardian> findByUsername(String username);
    boolean existsByUsername(String username);
}
```

`backend/src/main/java/com/weniv/falls/repository/AuthTokenRepository.java` (새 파일):

```java
// 토큰 조회 — PK가 key 문자열이라 findById(key)가 곧 토큰 대조다
package com.weniv.falls.repository;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import com.weniv.falls.domain.AuthToken;

public interface AuthTokenRepository extends JpaRepository<AuthToken, String> {
    Optional<AuthToken> findByGuardianId(Long guardianId);
}
```

`backend/src/main/java/com/weniv/falls/repository/FallEventRepository.java` (새 파일):

```java
// 낙상 이벤트 조회 — 소유자 필터·최신순·멱등 중복 조회
package com.weniv.falls.repository;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import com.weniv.falls.domain.FallEvent;

public interface FallEventRepository extends JpaRepository<FallEvent, Long> {
    List<FallEvent> findByGuardianIdOrderByIdDesc(Long guardianId);
    Optional<FallEvent> findByIdAndGuardianId(Long id, Long guardianId);
    Optional<FallEvent> findFirstByGuardianIdAndRoomNameAndRoomNumberAndOccurredAt(
        Long guardianId, String roomName, Integer roomNumber, Instant occurredAt);
}
```

`backend/src/main/java/com/weniv/falls/repository/RoomRepository.java` (새 파일):

```java
// 방 조회 — 소유자 필터·name,number 정렬·중복 사전 검사
package com.weniv.falls.repository;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import com.weniv.falls.domain.Room;

public interface RoomRepository extends JpaRepository<Room, Long> {
    List<Room> findByGuardianIdOrderByNameAscNumberAsc(Long guardianId);
    Optional<Room> findByIdAndGuardianId(Long id, Long guardianId);
    boolean existsByGuardianIdAndNameAndNumber(Long guardianId, String name, Integer number);
    boolean existsByGuardianIdAndNameAndNumberAndIdNot(Long guardianId, String name, Integer number, Long id);
}
```

`backend/src/main/java/com/weniv/falls/repository/GuardianProfileRepository.java` (새 파일):

```java
// 보호자 프로필 조회 — get-or-create용
package com.weniv.falls.repository;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import com.weniv.falls.domain.GuardianProfile;

public interface GuardianProfileRepository extends JpaRepository<GuardianProfile, Long> {
    Optional<GuardianProfile> findByGuardianId(Long guardianId);
}
```

`backend/src/main/java/com/weniv/falls/repository/PushDeviceRepository.java` (새 파일):

```java
// 푸시 기기 조회 — 토큰 유니크 기반 이전·소유자 발송 목록·해제
package com.weniv.falls.repository;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import com.weniv.falls.domain.PushDevice;

public interface PushDeviceRepository extends JpaRepository<PushDevice, Long> {
    Optional<PushDevice> findByToken(String token);
    List<PushDevice> findByGuardianId(Long guardianId);
    void deleteByGuardianIdAndToken(Long guardianId, String token);   // 호출부는 @Transactional 필요
}
```

- [ ] **Step 6: 테스트 통과 확인**

Run: `cd backend && ./gradlew test`
Expected: BUILD SUCCESSFUL — DomainConstraintTest 4개 + HealthApiTest 1개. Flyway가 `fall_detection_test`에 V1을 적용하고, TRUNCATE 베이스가 동작한다.

- [ ] **Step 7: 커밋**

```bash
git add backend/src/main/resources/db/migration backend/src/main/java/com/weniv/falls/domain \
  backend/src/main/java/com/weniv/falls/repository backend/src/test/java/com/weniv/falls
git commit -m "feat: 도메인 6종·Flyway V1·리포지토리 — 유니크 제약 이름 SQL 고정

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: 인증 — 토큰 필터·로그인·가입 + 에러 핸들러

DRF TokenAuthentication 등가 구현(스펙 6절)과 DRF 호환 에러 변환기(스펙 8절). 에러 핸들러는 이후 모든 API 태스크가 재사용한다.

**Files:**
- Create: `backend/src/main/resources/common-passwords.txt` (Django 내장 목록 상위 500개)
- Create: `backend/src/main/java/com/weniv/falls/error/FieldValidationException.java`, `NotFoundException.java`, `GlobalExceptionHandler.java`
- Create: `backend/src/main/java/com/weniv/falls/config/TokenAuthFilter.java`
- Modify: `backend/src/main/java/com/weniv/falls/config/SecurityConfig.java` (auth 경로 permitAll + 필터 등록)
- Create: `backend/src/main/java/com/weniv/falls/dto/LoginRequest.java`, `SignupRequest.java`, `TokenResponse.java`
- Create: `backend/src/main/java/com/weniv/falls/service/AuthService.java`
- Create: `backend/src/main/java/com/weniv/falls/controller/AuthController.java`
- Test: `backend/src/test/java/com/weniv/falls/AuthApiTest.java`

**Interfaces:**
- Consumes: Guardian/AuthToken 엔티티·리포지토리, `AuthToken.newKey()`, `PasswordEncoder`, IntegrationTestBase (Task 2)
- Produces:
  - `FieldValidationException(Map<String, List<String>> errors)` → 400 `{필드: [메시지…]}` — Task 4~7의 모든 검증 에러가 이걸 던진다
  - `NotFoundException()`(인자 없음) → 404 `{"detail": "찾을 수 없습니다."}`
  - `GlobalExceptionHandler` — `MethodArgumentNotValidException`도 400 `{snake_case필드: [메시지…]}`로 변환 (Bean Validation 쓰는 Task 5·7이 의존)
  - `SecurityConfig` 최종형 — `@AuthenticationPrincipal Guardian` 주입이 전 컨트롤러에서 동작
  - `AuthService.login(String, String) → String`(토큰 key), `AuthService.signup(String, String) → String`

- [ ] **Step 1: 공통 비밀번호 목록 추출 (Django venv가 살아있는 지금 시점에만 가능)**

```bash
cd /Users/munhokang/82107/weniv_project/backend
python3 -c "import gzip; print(gzip.open('.venv/lib/python3.14/site-packages/django/contrib/auth/common-passwords.txt.gz','rt').read(), end='')" \
  | head -500 > src/main/resources/common-passwords.txt
wc -l src/main/resources/common-passwords.txt
head -3 src/main/resources/common-passwords.txt
```

Expected: `500`, 첫 줄들은 `123456` `password` 류. (스펙 6절: 2만 개 전체 이식 대신 대표 수백 개.) Django가 소문자 비교하므로 목록도 소문자 그대로 둔다.

- [ ] **Step 2: 실패하는 인증 테스트 작성**

`backend/src/test/java/com/weniv/falls/AuthApiTest.java` (새 파일):

```java
// 인증 계약 테스트 — 401 형태·로그인 토큰·가입 즉시 발급·중복/약한 비밀번호 400
package com.weniv.falls;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;

class AuthApiTest extends IntegrationTestBase {

    @Test
    void anonymous_gets_401() throws Exception {
        mockMvc.perform(get("/api/falls/"))
            .andExpect(status().isUnauthorized())
            .andExpect(jsonPath("$.detail").exists());   // {"detail": "..."} 형태 고정
    }

    @Test
    void login_returns_token() throws Exception {
        mockMvc.perform(post("/api/auth/login/").contentType(MediaType.APPLICATION_JSON)
                .content("{\"username\": \"g1\", \"password\": \"pw12345\"}"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.token").isNotEmpty());
    }

    @Test
    void login_wrong_password_400() throws Exception {
        mockMvc.perform(post("/api/auth/login/").contentType(MediaType.APPLICATION_JSON)
                .content("{\"username\": \"g1\", \"password\": \"wrong-pass\"}"))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.non_field_errors").isArray());
    }

    // Task 7에서 "그 토큰으로 GET /api/falls/ 200" 검증이 추가된다 (엔드포인트가 그때 생긴다)
    @Test
    void signup_returns_token_and_logs_in() throws Exception {
        mockMvc.perform(post("/api/auth/signup/").contentType(MediaType.APPLICATION_JSON)
                .content("{\"username\": \"new1\", \"password\": \"tough-pass-9x\"}"))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.token").isNotEmpty());
    }

    @Test
    void signup_duplicate_username_400() throws Exception {
        // g1은 베이스 픽스처로 이미 존재한다
        mockMvc.perform(post("/api/auth/signup/").contentType(MediaType.APPLICATION_JSON)
                .content("{\"username\": \"g1\", \"password\": \"tough-pass-9x\"}"))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.username").isArray());
    }

    @Test
    void signup_weak_password_400() throws Exception {
        // 8자 미만·전부 숫자·흔한 비밀번호 — 셋 다 걸리는 입력
        mockMvc.perform(post("/api/auth/signup/").contentType(MediaType.APPLICATION_JSON)
                .content("{\"username\": \"new2\", \"password\": \"1234\"}"))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.password").isArray());
    }
}
```

- [ ] **Step 3: 테스트 실패 확인**

Run: `cd backend && ./gradlew test --tests "com.weniv.falls.AuthApiTest"`
Expected: FAIL — `/api/auth/login/`이 permitAll이 아니라 401, 컨트롤러 미존재.

- [ ] **Step 4: 에러 계층 구현**

`backend/src/main/java/com/weniv/falls/error/FieldValidationException.java` (새 파일):

```java
// DRF ValidationError 등가 — {필드: [메시지…]} 맵을 그대로 400 본문으로 내린다
package com.weniv.falls.error;

import java.util.List;
import java.util.Map;

public class FieldValidationException extends RuntimeException {

    private final Map<String, List<String>> errors;

    public FieldValidationException(Map<String, List<String>> errors) {
        super(errors.toString());
        this.errors = errors;
    }

    public Map<String, List<String>> getErrors() {
        return errors;
    }
}
```

`backend/src/main/java/com/weniv/falls/error/NotFoundException.java` (새 파일):

```java
// 소유권 밖·미존재 리소스 — 404 {"detail": "..."}로 변환된다
package com.weniv.falls.error;

public class NotFoundException extends RuntimeException {
}
```

`backend/src/main/java/com/weniv/falls/error/GlobalExceptionHandler.java` (새 파일):

```java
// 모든 예외를 DRF 호환 JSON으로 변환 — 클라이언트 firstErrorMessage()가 그대로 동작해야 한다
package com.weniv.falls.error;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(FieldValidationException.class)
    ResponseEntity<Map<String, List<String>>> handleFieldValidation(FieldValidationException ex) {
        return ResponseEntity.badRequest().body(ex.getErrors());
    }

    @ExceptionHandler(NotFoundException.class)
    ResponseEntity<Map<String, String>> handleNotFound(NotFoundException ex) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of("detail", "찾을 수 없습니다."));
    }

    // Bean Validation(@Valid) 실패 — 필드명을 snake_case로 바꿔 {필드: [메시지…]}로 그룹핑
    @ExceptionHandler(MethodArgumentNotValidException.class)
    ResponseEntity<Map<String, List<String>>> handleBeanValidation(MethodArgumentNotValidException ex) {
        Map<String, List<String>> errors = new LinkedHashMap<>();
        for (FieldError fe : ex.getBindingResult().getFieldErrors()) {
            errors.computeIfAbsent(snakeCase(fe.getField()), k -> new ArrayList<>())
                .add(fe.getDefaultMessage());
        }
        return ResponseEntity.badRequest().body(errors);
    }

    // 본문이 JSON이 아니거나 타입이 안 맞는 경우 — 클라이언트는 상태 코드만 본다
    @ExceptionHandler(HttpMessageNotReadableException.class)
    ResponseEntity<Map<String, String>> handleUnreadable(HttpMessageNotReadableException ex) {
        return ResponseEntity.badRequest().body(Map.of("detail", "요청 본문을 해석할 수 없습니다."));
    }

    private static String snakeCase(String field) {
        return field.replaceAll("([a-z0-9])([A-Z])", "$1_$2").toLowerCase();
    }
}
```

- [ ] **Step 5: 토큰 필터 + SecurityConfig 최종형**

`backend/src/main/java/com/weniv/falls/config/TokenAuthFilter.java` (새 파일 — `@Component`를 붙이지 않는다. 붙이면 Boot이 서블릿 필터로도 자동 등록해 요청마다 두 번 실행된다. SecurityConfig가 직접 생성한다):

```java
// Authorization: Token <key> 헤더를 AuthToken 테이블과 대조해 SecurityContext에 보호자를 넣는다
package com.weniv.falls.config;

import java.io.IOException;
import java.util.List;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

import com.weniv.falls.repository.AuthTokenRepository;

public class TokenAuthFilter extends OncePerRequestFilter {

    private static final String PREFIX = "Token ";

    private final AuthTokenRepository authTokenRepository;

    public TokenAuthFilter(AuthTokenRepository authTokenRepository) {
        this.authTokenRepository = authTokenRepository;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        String header = request.getHeader("Authorization");
        if (header != null && header.startsWith(PREFIX)) {
            String key = header.substring(PREFIX.length()).trim();
            // 키가 틀리면 컨텍스트를 비워둔 채 통과 — 뒤의 인가 단계가 401 엔트리포인트로 보낸다
            authTokenRepository.findById(key).ifPresent(token ->
                SecurityContextHolder.getContext().setAuthentication(
                    new UsernamePasswordAuthenticationToken(token.getGuardian(), null, List.of())));
        }
        chain.doFilter(request, response);
    }
}
```

`backend/src/main/java/com/weniv/falls/config/SecurityConfig.java`의 `filterChain` 메서드를 다음으로 교체 (import에 `org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter`와 `com.weniv.falls.repository.AuthTokenRepository` 추가):

```java
    @Bean
    SecurityFilterChain filterChain(HttpSecurity http, AuthTokenRepository authTokenRepository)
            throws Exception {
        http
            .csrf(csrf -> csrf.disable())
            .cors(Customizer.withDefaults())
            .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .httpBasic(b -> b.disable())
            .formLogin(f -> f.disable())
            .authorizeHttpRequests(auth -> auth
                // permitAll은 이 셋뿐 (스펙 6절) — 나머지는 전부 인증 필수
                .requestMatchers("/", "/api/auth/login/", "/api/auth/signup/").permitAll()
                .anyRequest().authenticated())
            .exceptionHandling(e -> e.authenticationEntryPoint(SecurityConfig::unauthorized))
            .addFilterBefore(new TokenAuthFilter(authTokenRepository),
                UsernamePasswordAuthenticationFilter.class);
        return http.build();
    }
```

- [ ] **Step 6: DTO + AuthService + AuthController 구현**

`backend/src/main/java/com/weniv/falls/dto/LoginRequest.java` (새 파일):

```java
// 로그인 요청 — 필수 검증은 Bean Validation, 자격 대조는 AuthService
package com.weniv.falls.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.validation.constraints.NotBlank;

@JsonIgnoreProperties(ignoreUnknown = true)
public record LoginRequest(
    @NotBlank(message = "이 필드는 필수 항목입니다.") String username,
    @NotBlank(message = "이 필드는 필수 항목입니다.") String password) {
}
```

`backend/src/main/java/com/weniv/falls/dto/SignupRequest.java` (새 파일):

```java
// 가입 요청 — 검증 규칙이 조건부(Django 등가)라 AuthService가 직접 검증한다
package com.weniv.falls.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

@JsonIgnoreProperties(ignoreUnknown = true)
public record SignupRequest(String username, String password) {
}
```

`backend/src/main/java/com/weniv/falls/dto/TokenResponse.java` (새 파일):

```java
// 로그인·가입 응답 — {"token": "<40자 hex>"}
package com.weniv.falls.dto;

public record TokenResponse(String token) {
}
```

`backend/src/main/java/com/weniv/falls/service/AuthService.java` (새 파일):

```java
// 로그인·가입 — BCrypt 대조, 토큰 get-or-create, Django 등가 가입 검증(한국어 메시지)
package com.weniv.falls.service;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import org.springframework.core.io.ClassPathResource;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import com.weniv.falls.domain.AuthToken;
import com.weniv.falls.domain.Guardian;
import com.weniv.falls.error.FieldValidationException;
import com.weniv.falls.repository.AuthTokenRepository;
import com.weniv.falls.repository.GuardianRepository;

@Service
public class AuthService {

    // Java의 \w는 ASCII 전용이라 스펙 6절의 "영숫자와 @.+-_"와 정확히 일치한다
    private static final Pattern USERNAME_PATTERN = Pattern.compile("^[\\w.@+-]+$");
    private static final String REQUIRED_MESSAGE = "이 필드는 필수 항목입니다.";

    private final GuardianRepository guardianRepository;
    private final AuthTokenRepository authTokenRepository;
    private final PasswordEncoder passwordEncoder;
    private final Set<String> commonPasswords;

    public AuthService(GuardianRepository guardianRepository,
                       AuthTokenRepository authTokenRepository,
                       PasswordEncoder passwordEncoder) {
        this.guardianRepository = guardianRepository;
        this.authTokenRepository = authTokenRepository;
        this.passwordEncoder = passwordEncoder;
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(
                new ClassPathResource("common-passwords.txt").getInputStream(), StandardCharsets.UTF_8))) {
            this.commonPasswords = reader.lines()
                .map(String::trim)
                .filter(line -> !line.isEmpty())
                .collect(Collectors.toUnmodifiableSet());
        } catch (IOException e) {
            throw new UncheckedIOException("common-passwords.txt 로드 실패", e);
        }
    }

    public String login(String username, String password) {
        return guardianRepository.findByUsername(username)
            .filter(g -> passwordEncoder.matches(password, g.getPassword()))
            .map(this::tokenFor)
            .orElseThrow(() -> new FieldValidationException(
                Map.of("non_field_errors", List.of("제공된 자격 증명으로 로그인할 수 없습니다."))));
    }

    public String signup(String username, String password) {
        Map<String, List<String>> errors = new LinkedHashMap<>();

        List<String> usernameErrors = new ArrayList<>();
        if (username == null || username.isBlank()) {
            usernameErrors.add(REQUIRED_MESSAGE);
        } else {
            if (username.length() > 150) {
                usernameErrors.add("이 필드의 글자 수가 150 이하인지 확인하십시오.");
            }
            if (!USERNAME_PATTERN.matcher(username).matches()) {
                usernameErrors.add("유효한 사용자 이름을 입력하십시오. 문자, 숫자, @/./+/-/_만 가능합니다.");
            }
            if (guardianRepository.existsByUsername(username)) {
                usernameErrors.add("해당 사용자 이름은 이미 존재합니다.");
            }
        }

        List<String> passwordErrors = new ArrayList<>();
        if (password == null || password.isBlank()) {
            passwordErrors.add(REQUIRED_MESSAGE);
        } else {
            if (password.length() < 8) {
                passwordErrors.add("비밀번호가 너무 짧습니다. 최소 8자를 포함해야 합니다.");
            }
            if (password.chars().allMatch(Character::isDigit)) {
                passwordErrors.add("비밀번호가 전부 숫자로 되어 있습니다.");
            }
            if (commonPasswords.contains(password.toLowerCase())) {
                passwordErrors.add("비밀번호가 너무 일상적인 단어입니다.");
            }
        }

        if (!usernameErrors.isEmpty()) errors.put("username", usernameErrors);
        if (!passwordErrors.isEmpty()) errors.put("password", passwordErrors);
        if (!errors.isEmpty()) throw new FieldValidationException(errors);

        try {
            Guardian guardian = guardianRepository.saveAndFlush(
                new Guardian(username, passwordEncoder.encode(password)));
            return tokenFor(guardian);
        } catch (DataIntegrityViolationException e) {
            // 가입 경합 — 사전 검사와 저장 사이에 같은 username이 들어온 경우도 같은 400
            throw new FieldValidationException(
                Map.of("username", List.of("해당 사용자 이름은 이미 존재합니다.")));
        }
    }

    // DRF Token.objects.get_or_create 등가 — 재로그인해도 같은 키를 돌려준다
    private String tokenFor(Guardian guardian) {
        return authTokenRepository.findByGuardianId(guardian.getId())
            .orElseGet(() -> authTokenRepository.save(new AuthToken(AuthToken.newKey(), guardian)))
            .getKey();
    }
}
```

`backend/src/main/java/com/weniv/falls/controller/AuthController.java` (새 파일):

```java
// 로그인·가입 엔드포인트 — 가입 즉시 토큰을 돌려줘 클라이언트가 로그인을 한 번 더 안 해도 된다
package com.weniv.falls.controller;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import com.weniv.falls.dto.LoginRequest;
import com.weniv.falls.dto.SignupRequest;
import com.weniv.falls.dto.TokenResponse;
import com.weniv.falls.service.AuthService;

@RestController
public class AuthController {

    private final AuthService authService;

    public AuthController(AuthService authService) {
        this.authService = authService;
    }

    @PostMapping("/api/auth/login/")
    public TokenResponse login(@Valid @RequestBody LoginRequest request) {
        return new TokenResponse(authService.login(request.username(), request.password()));
    }

    @PostMapping("/api/auth/signup/")
    public ResponseEntity<TokenResponse> signup(@RequestBody SignupRequest request) {
        String token = authService.signup(request.username(), request.password());
        return ResponseEntity.status(HttpStatus.CREATED).body(new TokenResponse(token));
    }
}
```

- [ ] **Step 7: 테스트 통과 확인**

Run: `cd backend && ./gradlew test`
Expected: BUILD SUCCESSFUL — AuthApiTest 6개 포함 전체 11개 통과.

- [ ] **Step 8: 커밋**

```bash
git add backend/src/main/resources/common-passwords.txt \
  backend/src/main/java/com/weniv/falls/error backend/src/main/java/com/weniv/falls/config \
  backend/src/main/java/com/weniv/falls/dto backend/src/main/java/com/weniv/falls/service \
  backend/src/main/java/com/weniv/falls/controller backend/src/test/java/com/weniv/falls/AuthApiTest.java
git commit -m "feat: 토큰 인증·로그인·가입 — DRF TokenAuthentication 등가, 한국어 검증 메시지

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: 방 CRUD + 프로필 API

방 중복은 사전 검사로 400을 만들고, 경합으로 유니크 제약에 걸린 경우도 같은 400으로 변환한다(스펙 8절 — 문자열까지 고정). PATCH는 부분 수정(웹은 `{name}`만 보낸다), PUT은 전체 수정이라 RoomRequest 검증이 조건부다 — Bean Validation 대신 서비스가 직접 검증해 `FieldValidationException`을 던진다.

**Files:**
- Create: `backend/src/main/java/com/weniv/falls/dto/RoomRequest.java`, `RoomResponse.java`, `ProfileDto.java`
- Create: `backend/src/main/java/com/weniv/falls/service/RoomService.java`, `ProfileService.java`
- Create: `backend/src/main/java/com/weniv/falls/controller/RoomController.java`, `ProfileController.java`
- Test: `backend/src/test/java/com/weniv/falls/RoomApiTest.java`, `ProfileApiTest.java`

**Interfaces:**
- Consumes: Room/GuardianProfile 엔티티·리포지토리(Task 2), `FieldValidationException`·`NotFoundException`(Task 3), `@AuthenticationPrincipal Guardian`(Task 3 필터)
- Produces:
  - `RoomService.DUPLICATE_ROOM_MESSAGE` = `"같은 이름과 번호의 방이 이미 있습니다."` (public static final)
  - `RoomService.list/get/create/update(partial)/delete`
  - `ProfileService.get(Guardian) → ProfileDto`, `update(Guardian, ProfileDto) → ProfileDto`

- [ ] **Step 1: 실패하는 방·프로필 테스트 작성**

`backend/src/test/java/com/weniv/falls/RoomApiTest.java` (새 파일):

```java
// 방 CRUD 계약 테스트 — 소유권 격리·중복 400(문자열 고정)·경합 안전망
package com.weniv.falls;

import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doReturn;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;

import com.jayway.jsonpath.JsonPath;
import com.weniv.falls.domain.Room;
import com.weniv.falls.repository.RoomRepository;

class RoomApiTest extends IntegrationTestBase {

    // 베이스의 roomRepository와 같은 빈 — 경합 테스트에서 사전 검사만 골라 무력화한다
    @MockitoSpyBean
    RoomRepository roomRepositorySpy;

    @Test
    void room_crud_roundtrip() throws Exception {
        String body = mockMvc.perform(authed(post("/api/rooms/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\": \"안방\", \"number\": 1}"))
            .andExpect(status().isCreated())
            .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        int roomId = JsonPath.read(body, "$.id");

        mockMvc.perform(authed(get("/api/rooms/"), guardian))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.length()").value(1))
            .andExpect(jsonPath("$[0].name").value("안방"));

        mockMvc.perform(authed(patch("/api/rooms/" + roomId + "/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\": \"서재\"}"))   // 웹은 name만 보낸다 — 부분 수정
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.name").value("서재"));

        mockMvc.perform(authed(delete("/api/rooms/" + roomId + "/"), guardian))
            .andExpect(status().isNoContent());

        mockMvc.perform(authed(get("/api/rooms/"), guardian))
            .andExpect(jsonPath("$.length()").value(0));
    }

    @Test
    void room_list_excludes_other_users() throws Exception {
        roomRepository.save(new Room(other, "부엌", 1));
        mockMvc.perform(authed(get("/api/rooms/"), guardian))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.length()").value(0));
    }

    @Test
    void room_patch_other_users_404() throws Exception {
        Room theirs = roomRepository.save(new Room(other, "부엌", 1));
        mockMvc.perform(authed(patch("/api/rooms/" + theirs.getId() + "/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\": \"x\"}"))
            .andExpect(status().isNotFound());
    }

    @Test
    void room_duplicate_create_400() throws Exception {
        roomRepository.save(new Room(guardian, "안방", 1));
        mockMvc.perform(authed(post("/api/rooms/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\": \"안방\", \"number\": 1}"))
            .andExpect(status().isBadRequest());
    }

    @Test
    void room_duplicate_race_returns_400() throws Exception {
        // 사전 검사를 우회해 경합 시 안전망(DataIntegrityViolationException → 400)을 직접 검증한다
        roomRepository.save(new Room(guardian, "안방", 1));
        doReturn(false).when(roomRepositorySpy)
            .existsByGuardianIdAndNameAndNumber(anyLong(), anyString(), anyInt());
        mockMvc.perform(authed(post("/api/rooms/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\": \"안방\", \"number\": 1}"))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.non_field_errors.length()").value(1))
            .andExpect(jsonPath("$.non_field_errors[0]").value("같은 이름과 번호의 방이 이미 있습니다."));
    }
}
```

`backend/src/test/java/com/weniv/falls/ProfileApiTest.java` (새 파일):

```java
// 프로필 계약 테스트 — 접근 시 get-or-create, PUT 왕복
package com.weniv.falls;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;

class ProfileApiTest extends IntegrationTestBase {

    @Test
    void profile_get_creates_empty() throws Exception {
        mockMvc.perform(authed(get("/api/profile/"), guardian))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.length()").value(1))   // 응답 필드는 elder_phone 하나뿐
            .andExpect(jsonPath("$.elder_phone").value(""));
        assertThat(guardianProfileRepository.findByGuardianId(guardian.getId())).isPresent();
    }

    @Test
    void profile_put_roundtrip() throws Exception {
        mockMvc.perform(authed(put("/api/profile/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"elder_phone\": \"01012345678\"}"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.elder_phone").value("01012345678"));

        mockMvc.perform(authed(get("/api/profile/"), guardian))
            .andExpect(jsonPath("$.elder_phone").value("01012345678"));
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd backend && ./gradlew test --tests "com.weniv.falls.RoomApiTest" --tests "com.weniv.falls.ProfileApiTest"`
Expected: FAIL — 컴파일 오류 없이 401/404가 아니라, 컨트롤러 미존재로 인한 404. (컴파일은 통과 — 테스트가 참조하는 타입은 전부 Task 2 산출물이다.)

- [ ] **Step 3: DTO + 서비스 + 컨트롤러 구현**

`backend/src/main/java/com/weniv/falls/dto/RoomRequest.java` (새 파일):

```java
// 방 생성·수정 요청 — PATCH 부분 수정 때문에 필드가 nullable이고 검증은 RoomService가 한다
package com.weniv.falls.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

@JsonIgnoreProperties(ignoreUnknown = true)
public record RoomRequest(String name, Integer number) {
}
```

`backend/src/main/java/com/weniv/falls/dto/RoomResponse.java` (새 파일):

```java
// 방 응답 — {"id", "name", "number"}
package com.weniv.falls.dto;

import com.weniv.falls.domain.Room;

public record RoomResponse(Long id, String name, Integer number) {

    public static RoomResponse from(Room room) {
        return new RoomResponse(room.getId(), room.getName(), room.getNumber());
    }
}
```

`backend/src/main/java/com/weniv/falls/dto/ProfileDto.java` (새 파일):

```java
// 프로필 요청·응답 겸용 — {"elder_phone"} 하나뿐
package com.weniv.falls.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

import com.weniv.falls.domain.GuardianProfile;

@JsonIgnoreProperties(ignoreUnknown = true)
public record ProfileDto(@JsonProperty("elder_phone") String elderPhone) {

    public static ProfileDto from(GuardianProfile profile) {
        return new ProfileDto(profile.getElderPhone());
    }
}
```

`backend/src/main/java/com/weniv/falls/service/RoomService.java` (새 파일):

```java
// 방 CRUD — 소유권 필터 조회(남의 방은 404), 중복 사전 검사 + 경합 안전망(둘 다 같은 400)
package com.weniv.falls.service;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;

import com.weniv.falls.domain.Guardian;
import com.weniv.falls.domain.Room;
import com.weniv.falls.dto.RoomRequest;
import com.weniv.falls.error.FieldValidationException;
import com.weniv.falls.error.NotFoundException;
import com.weniv.falls.repository.RoomRepository;

@Service
public class RoomService {

    public static final String DUPLICATE_ROOM_MESSAGE = "같은 이름과 번호의 방이 이미 있습니다.";
    private static final String REQUIRED_MESSAGE = "이 필드는 필수 항목입니다.";

    private final RoomRepository roomRepository;

    public RoomService(RoomRepository roomRepository) {
        this.roomRepository = roomRepository;
    }

    public List<Room> list(Guardian guardian) {
        return roomRepository.findByGuardianIdOrderByNameAscNumberAsc(guardian.getId());
    }

    public Room get(Guardian guardian, Long id) {
        // guardian 조건을 건 조회 — 남의 방은 존재 자체가 드러나지 않고 404가 된다
        return roomRepository.findByIdAndGuardianId(id, guardian.getId())
            .orElseThrow(NotFoundException::new);
    }

    public Room create(Guardian guardian, RoomRequest request) {
        validate(request, true);
        if (roomRepository.existsByGuardianIdAndNameAndNumber(
                guardian.getId(), request.name(), request.number())) {
            throw duplicate();
        }
        try {
            // saveAndFlush — 제약 위반을 이 자리에서 잡아 400으로 바꾸기 위해 즉시 flush한다
            return roomRepository.saveAndFlush(new Room(guardian, request.name(), request.number()));
        } catch (DataIntegrityViolationException e) {
            throw duplicate();   // 사전 검사와 저장 사이의 경합도 같은 400
        }
    }

    public Room update(Guardian guardian, Long id, RoomRequest request, boolean partial) {
        Room room = get(guardian, id);
        validate(request, !partial);
        String name = request.name() != null ? request.name() : room.getName();
        Integer number = request.number() != null ? request.number() : room.getNumber();
        if (roomRepository.existsByGuardianIdAndNameAndNumberAndIdNot(
                guardian.getId(), name, number, room.getId())) {
            throw duplicate();
        }
        room.rename(name, number);
        try {
            return roomRepository.saveAndFlush(room);
        } catch (DataIntegrityViolationException e) {
            throw duplicate();
        }
    }

    public void delete(Guardian guardian, Long id) {
        roomRepository.delete(get(guardian, id));
    }

    private FieldValidationException duplicate() {
        return new FieldValidationException(
            Map.of("non_field_errors", List.of(DUPLICATE_ROOM_MESSAGE)));
    }

    // requireAll=true(POST·PUT)면 누락도 에러, false(PATCH)면 보낸 필드만 검사한다
    private void validate(RoomRequest request, boolean requireAll) {
        Map<String, List<String>> errors = new LinkedHashMap<>();

        List<String> nameErrors = new ArrayList<>();
        if (request.name() == null) {
            if (requireAll) nameErrors.add(REQUIRED_MESSAGE);
        } else {
            if (request.name().isBlank()) nameErrors.add(REQUIRED_MESSAGE);
            if (request.name().length() > 20) {
                nameErrors.add("이 필드의 글자 수가 20 이하인지 확인하십시오.");
            }
        }

        List<String> numberErrors = new ArrayList<>();
        if (request.number() == null) {
            if (requireAll) numberErrors.add(REQUIRED_MESSAGE);
        } else if (request.number() < 0 || request.number() > 32767) {
            numberErrors.add("이 값이 0 이상 32767 이하인지 확인하십시오.");
        }

        if (!nameErrors.isEmpty()) errors.put("name", nameErrors);
        if (!numberErrors.isEmpty()) errors.put("number", numberErrors);
        if (!errors.isEmpty()) throw new FieldValidationException(errors);
    }
}
```

`backend/src/main/java/com/weniv/falls/service/ProfileService.java` (새 파일):

```java
// 보호자 프로필 — 접근 시 get-or-create (Django GuardianProfile.objects.get_or_create 등가)
package com.weniv.falls.service;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;

import com.weniv.falls.domain.Guardian;
import com.weniv.falls.domain.GuardianProfile;
import com.weniv.falls.dto.ProfileDto;
import com.weniv.falls.repository.GuardianProfileRepository;

@Service
public class ProfileService {

    private final GuardianProfileRepository profileRepository;

    public ProfileService(GuardianProfileRepository profileRepository) {
        this.profileRepository = profileRepository;
    }

    public ProfileDto get(Guardian guardian) {
        return ProfileDto.from(getOrCreate(guardian));
    }

    public ProfileDto update(Guardian guardian, ProfileDto request) {
        GuardianProfile profile = getOrCreate(guardian);
        // Django와 동일 — 필드가 아예 없으면(null) 기존 값을 유지한다 (클라이언트는 항상 보낸다)
        if (request.elderPhone() != null) {
            profile.updatePhone(request.elderPhone());
            profileRepository.save(profile);
        }
        return ProfileDto.from(profile);
    }

    private GuardianProfile getOrCreate(Guardian guardian) {
        return profileRepository.findByGuardianId(guardian.getId()).orElseGet(() -> {
            try {
                return profileRepository.saveAndFlush(new GuardianProfile(guardian));
            } catch (DataIntegrityViolationException e) {
                // get_or_create 경합 — 동시에 만들어졌으면 그 행을 쓴다
                return profileRepository.findByGuardianId(guardian.getId()).orElseThrow();
            }
        });
    }
}
```

`backend/src/main/java/com/weniv/falls/controller/RoomController.java` (새 파일):

```java
// 방 CRUD 엔드포인트 — 끝 슬래시 포함 경로·상태 코드가 기존 계약 그대로다
package com.weniv.falls.controller;

import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import com.weniv.falls.domain.Guardian;
import com.weniv.falls.dto.RoomRequest;
import com.weniv.falls.dto.RoomResponse;
import com.weniv.falls.service.RoomService;

@RestController
public class RoomController {

    private final RoomService roomService;

    public RoomController(RoomService roomService) {
        this.roomService = roomService;
    }

    @GetMapping("/api/rooms/")
    public List<RoomResponse> list(@AuthenticationPrincipal Guardian guardian) {
        return roomService.list(guardian).stream().map(RoomResponse::from).toList();
    }

    @PostMapping("/api/rooms/")
    public ResponseEntity<RoomResponse> create(@AuthenticationPrincipal Guardian guardian,
                                               @RequestBody RoomRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED)
            .body(RoomResponse.from(roomService.create(guardian, request)));
    }

    @GetMapping("/api/rooms/{id}/")
    public RoomResponse get(@AuthenticationPrincipal Guardian guardian, @PathVariable Long id) {
        return RoomResponse.from(roomService.get(guardian, id));
    }

    @PutMapping("/api/rooms/{id}/")
    public RoomResponse put(@AuthenticationPrincipal Guardian guardian, @PathVariable Long id,
                            @RequestBody RoomRequest request) {
        return RoomResponse.from(roomService.update(guardian, id, request, false));
    }

    @PatchMapping("/api/rooms/{id}/")
    public RoomResponse patch(@AuthenticationPrincipal Guardian guardian, @PathVariable Long id,
                              @RequestBody RoomRequest request) {
        return RoomResponse.from(roomService.update(guardian, id, request, true));
    }

    @DeleteMapping("/api/rooms/{id}/")
    public ResponseEntity<Void> delete(@AuthenticationPrincipal Guardian guardian,
                                       @PathVariable Long id) {
        roomService.delete(guardian, id);
        return ResponseEntity.noContent().build();   // 204
    }
}
```

`backend/src/main/java/com/weniv/falls/controller/ProfileController.java` (새 파일):

```java
// 프로필 엔드포인트 — GET·PUT 모두 {"elder_phone"} 하나를 주고받는다
package com.weniv.falls.controller;

import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import com.weniv.falls.domain.Guardian;
import com.weniv.falls.dto.ProfileDto;
import com.weniv.falls.service.ProfileService;

@RestController
public class ProfileController {

    private final ProfileService profileService;

    public ProfileController(ProfileService profileService) {
        this.profileService = profileService;
    }

    @GetMapping("/api/profile/")
    public ProfileDto get(@AuthenticationPrincipal Guardian guardian) {
        return profileService.get(guardian);
    }

    @PutMapping("/api/profile/")
    public ProfileDto put(@AuthenticationPrincipal Guardian guardian,
                          @Valid @RequestBody ProfileDto request) {
        return profileService.update(guardian, request);
    }
}
```

ProfileDto의 `elderPhone`에는 `@Size` 검증을 붙이지 않았다 — DB가 varchar(20)이라 20자 초과 PUT은 저장 시점에 `DataIntegrityViolationException`으로 500이 될 수 있다. Django는 시리얼라이저 max_length로 400을 냈으므로, `ProfileDto`에 `@jakarta.validation.constraints.Size(max = 20, message = "이 필드의 글자 수가 20 이하인지 확인하십시오.")`를 `elderPhone` 컴포넌트에 추가한다(위 `@Valid`가 발동시킨다). 최종 코드는 다음과 같다.

```java
@JsonIgnoreProperties(ignoreUnknown = true)
public record ProfileDto(
    @JsonProperty("elder_phone")
    @Size(max = 20, message = "이 필드의 글자 수가 20 이하인지 확인하십시오.")
    String elderPhone) {

    public static ProfileDto from(GuardianProfile profile) {
        return new ProfileDto(profile.getElderPhone());
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd backend && ./gradlew test`
Expected: BUILD SUCCESSFUL — RoomApiTest 5개 + ProfileApiTest 2개 포함 전체 18개 통과.

- [ ] **Step 5: 커밋**

```bash
git add backend/src/main/java/com/weniv/falls backend/src/test/java/com/weniv/falls
git commit -m "feat: 방 CRUD·프로필 API — 중복 400 문자열·소유권 404·get-or-create 보존

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: 푸시 기기 등록·해제 API

발송 로직 없는 순수 CRUD다. 토큰이 다른 계정에 있으면 현 사용자로 이전(계정 전환 케이스), 해제는 없는 토큰이어도 204(로그아웃을 막지 않는다).

**Files:**
- Create: `backend/src/main/java/com/weniv/falls/dto/PushDeviceRequest.java`, `PushDeviceDeleteRequest.java`
- Create: `backend/src/main/java/com/weniv/falls/service/PushDeviceService.java`
- Create: `backend/src/main/java/com/weniv/falls/controller/PushController.java` (vapid-key는 Task 6에서 추가)
- Test: `backend/src/test/java/com/weniv/falls/PushDeviceApiTest.java`

**Interfaces:**
- Consumes: PushDevice 엔티티·리포지토리(Task 2), `GlobalExceptionHandler`의 Bean Validation 변환(Task 3)
- Produces: `PushDeviceService.register(Guardian, String kind, String token)`, `unregister(Guardian, String token)` — Task 6이 PushController에 vapid-key 핸들러를 추가한다

- [ ] **Step 1: 실패하는 기기 등록 테스트 작성**

`backend/src/test/java/com/weniv/falls/PushDeviceApiTest.java` (새 파일):

```java
// 푸시 기기 등록·해제 계약 테스트 — 계정 이전·항상 204 해제·kind 검증
package com.weniv.falls;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;

import com.weniv.falls.domain.PushDevice;

class PushDeviceApiTest extends IntegrationTestBase {

    @Test
    void push_device_register() throws Exception {
        mockMvc.perform(authed(post("/api/push/devices/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"kind\": \"webpush\", \"token\": \"tok-1\"}"))
            .andExpect(status().isCreated());
        PushDevice device = pushDeviceRepository.findByToken("tok-1").orElseThrow();
        assertThat(device.getGuardian().getId()).isEqualTo(guardian.getId());
        assertThat(device.getKind()).isEqualTo("webpush");
    }

    @Test
    void push_device_token_moves_to_current_user() throws Exception {
        // 같은 브라우저에서 계정을 전환한 경우 — 토큰은 마지막 사용자 것이 된다
        mockMvc.perform(authed(post("/api/push/devices/"), other)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"kind\": \"webpush\", \"token\": \"tok-1\"}"))
            .andExpect(status().isCreated());
        mockMvc.perform(authed(post("/api/push/devices/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"kind\": \"webpush\", \"token\": \"tok-1\"}"))
            .andExpect(status().isCreated());
        assertThat(pushDeviceRepository.count()).isEqualTo(1);
        assertThat(pushDeviceRepository.findByToken("tok-1").orElseThrow().getGuardian().getId())
            .isEqualTo(guardian.getId());
    }

    @Test
    void push_device_delete() throws Exception {
        pushDeviceRepository.save(new PushDevice(guardian, "webpush", "tok-1"));
        mockMvc.perform(authed(delete("/api/push/devices/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"token\": \"tok-1\"}"))   // 비표준 DELETE body — 기존 계약
            .andExpect(status().isNoContent());
        assertThat(pushDeviceRepository.count()).isEqualTo(0);
    }

    @Test
    void push_device_bad_kind_400() throws Exception {
        // fcm은 Android 지원 제거로 더 이상 유효하지 않다
        for (String kind : new String[] {"smoke-signal", "fcm"}) {
            mockMvc.perform(authed(post("/api/push/devices/"), guardian)
                    .contentType(MediaType.APPLICATION_JSON)
                    .content("{\"kind\": \"" + kind + "\", \"token\": \"t\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.kind").isArray());
        }
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd backend && ./gradlew test --tests "com.weniv.falls.PushDeviceApiTest"`
Expected: FAIL — 엔드포인트 미존재(404).

- [ ] **Step 3: DTO + 서비스 + 컨트롤러 구현**

`backend/src/main/java/com/weniv/falls/dto/PushDeviceRequest.java` (새 파일):

```java
// 푸시 기기 등록 요청 — kind는 webpush만 유효 (DRF ChoiceField 등가)
package com.weniv.falls.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;

@JsonIgnoreProperties(ignoreUnknown = true)
public record PushDeviceRequest(
    @NotNull(message = "이 필드는 필수 항목입니다.")
    @Pattern(regexp = "webpush", message = "\"webpush\"만 유효한 선택입니다.")
    String kind,
    @NotBlank(message = "이 필드는 필수 항목입니다.")
    String token) {
}
```

`backend/src/main/java/com/weniv/falls/dto/PushDeviceDeleteRequest.java` (새 파일):

```java
// 푸시 기기 해제 요청 — DELETE body {"token"} (비표준이지만 기존 계약)
package com.weniv.falls.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

@JsonIgnoreProperties(ignoreUnknown = true)
public record PushDeviceDeleteRequest(String token) {
}
```

`backend/src/main/java/com/weniv/falls/service/PushDeviceService.java` (새 파일):

```java
// 푸시 기기 등록·해제 — update_or_create 등가(토큰 계정 이전), 해제는 소유자 것만 지운다
package com.weniv.falls.service;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.weniv.falls.domain.Guardian;
import com.weniv.falls.domain.PushDevice;
import com.weniv.falls.repository.PushDeviceRepository;

@Service
public class PushDeviceService {

    private final PushDeviceRepository pushDeviceRepository;

    public PushDeviceService(PushDeviceRepository pushDeviceRepository) {
        this.pushDeviceRepository = pushDeviceRepository;
    }

    @Transactional   // 조회한 엔티티의 필드 변경(dirty checking)까지 한 트랜잭션
    public void register(Guardian guardian, String kind, String token) {
        pushDeviceRepository.findByToken(token).ifPresentOrElse(
            device -> device.reassign(guardian, kind),   // 다른 계정에 있으면 현 사용자로 이전
            () -> pushDeviceRepository.save(new PushDevice(guardian, kind, token)));
    }

    @Transactional   // 파생 delete 쿼리는 트랜잭션이 필요하다
    public void unregister(Guardian guardian, String token) {
        // guardian 조건 포함 — 남의 기기는 지워지지 않지만 응답은 어차피 204다
        pushDeviceRepository.deleteByGuardianIdAndToken(guardian.getId(), token == null ? "" : token);
    }
}
```

`backend/src/main/java/com/weniv/falls/controller/PushController.java` (새 파일):

```java
// 푸시 기기 등록·해제 엔드포인트 (vapid-key는 발송 모듈과 함께 Task 6에서 추가)
package com.weniv.falls.controller;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import com.weniv.falls.domain.Guardian;
import com.weniv.falls.dto.PushDeviceDeleteRequest;
import com.weniv.falls.dto.PushDeviceRequest;
import com.weniv.falls.service.PushDeviceService;

@RestController
public class PushController {

    private final PushDeviceService pushDeviceService;

    public PushController(PushDeviceService pushDeviceService) {
        this.pushDeviceService = pushDeviceService;
    }

    @PostMapping("/api/push/devices/")
    public ResponseEntity<Void> register(@AuthenticationPrincipal Guardian guardian,
                                         @Valid @RequestBody PushDeviceRequest request) {
        pushDeviceService.register(guardian, request.kind(), request.token());
        return ResponseEntity.status(HttpStatus.CREATED).build();   // 201, 본문 없음 (기존 계약)
    }

    @DeleteMapping("/api/push/devices/")
    public ResponseEntity<Void> unregister(@AuthenticationPrincipal Guardian guardian,
                                           @RequestBody(required = false) PushDeviceDeleteRequest request) {
        // 없는 토큰·빈 본문이어도 204 — 로그아웃 흐름을 막지 않는다
        pushDeviceService.unregister(guardian, request == null ? null : request.token());
        return ResponseEntity.noContent().build();
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd backend && ./gradlew test`
Expected: BUILD SUCCESSFUL — PushDeviceApiTest 4개 포함 전체 22개 통과.

- [ ] **Step 5: 커밋**

```bash
git add backend/src/main/java/com/weniv/falls backend/src/test/java/com/weniv/falls
git commit -m "feat: 푸시 기기 등록·해제 API — 토큰 계정 이전·항상 204 해제 보존

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: 웹 푸시 발송 — VAPID 공개키 파생·@Async·만료 구독 정리

best-effort 원칙(스펙 7절): 발송 경로의 어떤 예외도 API 응답에 영향을 주지 않는다. 외부 HTTP를 치는 부분은 `WebPushClient` 인터페이스 뒤에 격리해 테스트가 목으로 막는다. 공개키는 BouncyCastle EC 연산으로 개인키에서 파생한다(서버에 공개키를 따로 두지 않는 기존 방식 보존).

**Files:**
- Modify: `backend/build.gradle` (web-push + BouncyCastle 의존성)
- Create: `backend/src/main/java/com/weniv/falls/service/VapidService.java`, `WebPushClient.java`, `MartijnDwarsWebPushClient.java`, `PushService.java`
- Create: `backend/src/main/java/com/weniv/falls/config/AsyncConfig.java`
- Create: `backend/src/main/java/com/weniv/falls/dto/VapidKeyResponse.java`
- Modify: `backend/src/main/java/com/weniv/falls/controller/PushController.java` (vapid-key 핸들러 추가)
- Test: `backend/src/test/java/com/weniv/falls/PushSendTest.java`, `PushSendDisabledTest.java`

**Interfaces:**
- Consumes: PushDevice 리포지토리(Task 2), FallEvent 엔티티(Task 2), PushController(Task 5), `push.vapid.*` 프로퍼티(Task 1 yml)
- Produces:
  - `VapidService.isConfigured() → boolean`, `publicKey() → String|null`(base64url 65바이트 비압축 점), `privateKey()`, `subject()`
  - `WebPushClient.send(String subscriptionJson, String payload) → int`(HTTP 상태 코드, throws Exception)
  - `PushService.sendToGuardianAsync(FallEvent)`(@Async), `sendToGuardian(FallEvent)`(동기, 테스트용) — Task 7의 FallController가 201일 때만 Async를 호출하고, FallApiTest가 이 빈을 목으로 바꾼다

- [ ] **Step 1: 의존성 추가**

`backend/build.gradle`의 `dependencies` 블록에 추가:

```groovy
	// 웹 푸시 — RFC 8291 암호화 발송. 구현 시점 최신판 확인: Maven Central 기준 5.1.2 (2026-07 확인)
	implementation('nl.martijndwars:web-push:5.1.2') {
		exclude group: 'org.bouncycastle', module: 'bcprov-jdk15on'   // 구세대 BC와 중복 방지
	}
	implementation 'org.bouncycastle:bcprov-jdk18on:1.80'
```

Run: `cd backend && ./gradlew compileJava`
Expected: BUILD SUCCESSFUL (의존성 해석 확인).

- [ ] **Step 2: 실패하는 발송 테스트 작성**

`backend/src/test/java/com/weniv/falls/PushSendTest.java` (새 파일 — VAPID 키가 설정된 컨텍스트):

```java
// 발송 경로 테스트 (키 설정 상태) — 만료 구독 삭제·실패 무해화·vapid-key 200
// pytest의 settings 변경 등가는 클래스 단위 @TestPropertySource다 (503 케이스는 PushSendDisabledTest)
package com.weniv.falls;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import com.jayway.jsonpath.JsonPath;
import com.weniv.falls.domain.PushDevice;
import com.weniv.falls.service.PushService;
import com.weniv.falls.service.WebPushClient;

@TestPropertySource(properties = {
    // pytest TEST_VAPID_KEY와 동일한 32바이트 스칼라(base64url)
    "push.vapid.private-key=AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE",
    "push.vapid.subject=mailto:test@example.com"
})
class PushSendTest extends IntegrationTestBase {

    @MockitoBean
    WebPushClient webPushClient;   // 실제 발송(외부 HTTP)만 목으로 막는다

    @Autowired
    PushService pushService;

    @Test
    void webpush_dead_subscription_deleted() throws Exception {
        PushDevice device = pushDeviceRepository.save(
            new PushDevice(guardian, "webpush", "{\"endpoint\": \"e\"}"));
        when(webPushClient.send(any(), any())).thenReturn(410);   // 만료 구독
        pushService.sendToGuardian(makeEvent(guardian));
        assertThat(pushDeviceRepository.findById(device.getId())).isEmpty();
    }

    @Test
    void send_failure_never_raises() throws Exception {
        pushDeviceRepository.save(new PushDevice(guardian, "webpush", "{\"endpoint\": \"e\"}"));
        when(webPushClient.send(any(), any())).thenThrow(new RuntimeException("boom"));
        // 예외가 새어나오면 테스트 실패 — best-effort 원칙
        assertThatCode(() -> pushService.sendToGuardian(makeEvent(guardian)))
            .doesNotThrowAnyException();
    }

    @Test
    void vapid_key_endpoint_returns_public_key() throws Exception {
        String body = mockMvc.perform(authed(get("/api/push/vapid-key/"), guardian))
            .andExpect(status().isOk())
            .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        String key = JsonPath.read(body, "$.key");
        assertThat(key.length()).isGreaterThan(40);   // base64url 공개키(65바이트 비압축 점)
    }
}
```

`backend/src/test/java/com/weniv/falls/PushSendDisabledTest.java` (새 파일 — 키 미설정 컨텍스트):

```java
// 발송 경로 테스트 (키 미설정 상태) — 발송 전체 스킵·vapid-key 503(문자열 고정)
package com.weniv.falls;

import static org.mockito.Mockito.verifyNoInteractions;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import com.weniv.falls.domain.PushDevice;
import com.weniv.falls.service.PushService;
import com.weniv.falls.service.WebPushClient;

@TestPropertySource(properties = {"push.vapid.private-key=", "push.vapid.subject="})
class PushSendDisabledTest extends IntegrationTestBase {

    @MockitoBean
    WebPushClient webPushClient;

    @Autowired
    PushService pushService;

    @Test
    void send_skips_when_vapid_unset() {
        pushDeviceRepository.save(new PushDevice(guardian, "webpush", "{\"endpoint\": \"e\"}"));
        pushService.sendToGuardian(makeEvent(guardian));
        verifyNoInteractions(webPushClient);   // 키가 없으면 발송 시도 자체가 없어야 한다
    }

    @Test
    void vapid_key_endpoint_503_when_unset() throws Exception {
        mockMvc.perform(authed(get("/api/push/vapid-key/"), guardian))
            .andExpect(status().isServiceUnavailable())
            .andExpect(jsonPath("$.detail").value("웹 푸시가 설정되지 않았습니다."));   // 문자열 고정
    }
}
```

- [ ] **Step 3: 테스트 실패 확인**

Run: `cd backend && ./gradlew test --tests "com.weniv.falls.PushSend*"`
Expected: FAIL — 컴파일 오류 (PushService·WebPushClient 미존재).

- [ ] **Step 4: VapidService + WebPushClient + PushService + AsyncConfig 구현**

`backend/src/main/java/com/weniv/falls/service/VapidService.java` (새 파일):

```java
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
```

`backend/src/main/java/com/weniv/falls/service/WebPushClient.java` (새 파일):

```java
// 웹 푸시 발송 어댑터 경계 — 테스트는 이 인터페이스를 목으로 바꿔 외부 HTTP를 차단한다
package com.weniv.falls.service;

public interface WebPushClient {

    /** 구독 JSON으로 페이로드를 발송하고 푸시 서비스의 HTTP 상태 코드를 돌려준다. */
    int send(String subscriptionJson, String payload) throws Exception;
}
```

`backend/src/main/java/com/weniv/falls/service/MartijnDwarsWebPushClient.java` (새 파일):

```java
// nl.martijndwars:web-push 어댑터 — 구독 JSON 파싱과 VAPID 서명 발송
// 주의: ObjectMapper import는 Task 1에서 확인한 Jackson 세대(tools.jackson 또는 com.fasterxml)에 맞춘다
package com.weniv.falls.service;

import org.springframework.stereotype.Component;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

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
            node.get("endpoint").asText(),
            new Subscription.Keys(
                node.at("/keys/p256dh").asText(),
                node.at("/keys/auth").asText()));
        var response = delegate().send(new Notification(subscription, payload));
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
```

라이브러리 5.1.2의 생성자·`send()` 반환 타입이 위와 다르면(예: `HttpResponse` 계열 변경) **이 파일 안에서만** 맞춰 고친다 — `WebPushClient` 인터페이스(상태 코드 int 반환)는 바꾸지 않는다. 그래야 PushService와 테스트가 영향을 받지 않는다.

`backend/src/main/java/com/weniv/falls/service/PushService.java` (새 파일):

```java
// 낙상 웹 푸시 발송 — best-effort: 어떤 예외도 API 응답에 영향을 주지 않는다 (앱 폴링이 안전망)
// 주의: ObjectMapper import는 Task 1에서 확인한 Jackson 세대에 맞춘다
package com.weniv.falls.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.databind.ObjectMapper;

import com.weniv.falls.domain.FallEvent;
import com.weniv.falls.domain.PushDevice;
import com.weniv.falls.repository.PushDeviceRepository;

@Service
public class PushService {

    private static final Logger log = LoggerFactory.getLogger(PushService.class);

    private final PushDeviceRepository pushDeviceRepository;
    private final VapidService vapidService;
    private final WebPushClient webPushClient;
    private final ObjectMapper objectMapper;

    public PushService(PushDeviceRepository pushDeviceRepository, VapidService vapidService,
                       WebPushClient webPushClient, ObjectMapper objectMapper) {
        this.pushDeviceRepository = pushDeviceRepository;
        this.vapidService = vapidService;
        this.webPushClient = webPushClient;
        this.objectMapper = objectMapper;
    }

    // POST 응답이 외부 HTTP를 기다리지 않도록 스레드풀에서 발송한다 (Django 데몬 스레드 등가)
    @Async("pushExecutor")
    public void sendToGuardianAsync(FallEvent event) {
        sendToGuardian(event);
    }

    public void sendToGuardian(FallEvent event) {
        try {
            if (!vapidService.isConfigured()) return;   // 키 미설정 — 조용히 비활성
            // LAZY 프록시라도 getId()는 초기화 없이 안전하다 (비동기 스레드에는 세션이 없다)
            Long guardianId = event.getGuardian().getId();
            for (PushDevice device : pushDeviceRepository.findByGuardianId(guardianId)) {
                sendOne(device, event);
            }
        } catch (Exception e) {
            log.error("푸시 발송 중 예상 밖 오류 (event={})", event.getId(), e);
        }
    }

    private void sendOne(PushDevice device, FallEvent event) {
        try {
            int status = webPushClient.send(device.getToken(), payloadJson(event));
            if (status == 404 || status == 410) {
                pushDeviceRepository.delete(device);   // 만료된 구독은 그 자리에서 정리한다
            } else if (status >= 400) {
                log.error("웹 푸시 발송 실패 (device={}, status={})", device.getId(), status);
            }
        } catch (Exception e) {
            log.error("웹 푸시 발송 실패 (device={})", device.getId(), e);
        }
    }

    // web/sw.js가 파싱하는 형태 — 키 이름·구성이 기존 계약이다
    private String payloadJson(FallEvent event) throws Exception {
        return objectMapper.writeValueAsString(new Payload(
            "fall", event.getId(), event.getRoomName(), event.getRoomNumber(),
            event.getOccurredAt().toString(), event.getConfidence()));
    }

    private record Payload(
        String type,
        Long id,
        @JsonProperty("room_name") String roomName,
        @JsonProperty("room_number") Integer roomNumber,
        @JsonProperty("occurred_at") String occurredAt,
        Double confidence) {
    }
}
```

`backend/src/main/java/com/weniv/falls/config/AsyncConfig.java` (새 파일):

```java
// 푸시 발송 전용 스레드풀 — 데몬 스레드라 서버 종료를 막지 않는다 (Django daemon=True 등가)
package com.weniv.falls.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

@Configuration
@EnableAsync
public class AsyncConfig {

    @Bean(name = "pushExecutor")
    ThreadPoolTaskExecutor pushExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(1);
        executor.setMaxPoolSize(2);
        executor.setQueueCapacity(100);
        executor.setThreadNamePrefix("push-");
        executor.setDaemon(true);
        return executor;
    }
}
```

`backend/src/main/java/com/weniv/falls/dto/VapidKeyResponse.java` (새 파일):

```java
// VAPID 공개키 응답 — {"key": "<base64url>"}
package com.weniv.falls.dto;

public record VapidKeyResponse(String key) {
}
```

`backend/src/main/java/com/weniv/falls/controller/PushController.java`에 핸들러 추가 — 생성자를 `PushController(PushDeviceService pushDeviceService, VapidService vapidService)`로 바꾸고(필드 추가), import에 `org.springframework.web.bind.annotation.GetMapping`, `java.util.Map`, `com.weniv.falls.dto.VapidKeyResponse`, `com.weniv.falls.service.VapidService`를 더한 뒤 메서드 추가:

```java
    @GetMapping("/api/push/vapid-key/")
    public ResponseEntity<?> vapidKey() {
        String key = vapidService.publicKey();
        if (key == null) {
            // 문자열 고정 (스펙 8절) — 보호자 페이지가 이 503으로 "미설정" 안내를 띄운다
            return ResponseEntity.status(503).body(Map.of("detail", "웹 푸시가 설정되지 않았습니다."));
        }
        return ResponseEntity.ok(new VapidKeyResponse(key));
    }
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `cd backend && ./gradlew test`
Expected: BUILD SUCCESSFUL — PushSendTest 3개 + PushSendDisabledTest 2개 포함 전체 27개 통과.

- [ ] **Step 6: 커밋**

```bash
git add backend/build.gradle backend/src/main/java/com/weniv/falls backend/src/test/java/com/weniv/falls
git commit -m "feat: 웹 푸시 발송 — VAPID 공개키 파생·@Async best-effort·만료 구독 정리

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: 낙상 API — 멱등 POST·acknowledge·푸시 트리거

오프라인 큐 재전송 멱등성의 핵심: 같은 낙상(guardian·room_name·room_number·occurred_at 일치)이 다시 오면 200 + 기존 행, 푸시 없음. FallService에 클래스 `@Transactional`을 **붙이지 않는다** — 유니크 제약 위반 시 PG 트랜잭션이 중단되는데, 리포지토리 호출이 각자 짧은 트랜잭션이면 위반 직후의 재조회가 새 트랜잭션에서 정상 동작한다(Django autocommit 등가).

**Files:**
- Create: `backend/src/main/java/com/weniv/falls/dto/FallEventRequest.java`, `FallEventResponse.java`
- Create: `backend/src/main/java/com/weniv/falls/service/FallService.java`
- Create: `backend/src/main/java/com/weniv/falls/controller/FallController.java`
- Modify: `backend/src/test/java/com/weniv/falls/AuthApiTest.java` (signup 테스트에 falls GET 검증 추가 — 원본 pytest 완전 복원)
- Test: `backend/src/test/java/com/weniv/falls/FallApiTest.java`

**Interfaces:**
- Consumes: FallEvent 엔티티·리포지토리(Task 2), `NotFoundException`(Task 3), `PushService.sendToGuardianAsync`(Task 6 — FallApiTest가 `@MockitoBean`으로 대체)
- Produces: `FallService.CreateResult(FallEvent event, boolean created)`, `FallService.list/create/acknowledge` — 마지막 API 태스크라 이후 소비자는 없다

- [ ] **Step 1: 실패하는 낙상 테스트 작성**

`backend/src/test/java/com/weniv/falls/FallApiTest.java` (새 파일):

```java
// 낙상 API 계약 테스트 — 목록 격리·최신순·guardian 강제·acknowledge 멱등·중복 POST 200·푸시 1회/0회
package com.weniv.falls;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.clearInvocations;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import com.jayway.jsonpath.JsonPath;
import com.weniv.falls.domain.FallEvent;
import com.weniv.falls.service.PushService;

class FallApiTest extends IntegrationTestBase {

    @MockitoBean
    PushService pushService;   // pytest의 send_to_guardian_async 목 등가 — 발송 호출 여부만 검증

    private String fallPayload(String confidence) {
        return "{\"room_name\": \"안방\", \"room_number\": 1, "
            + "\"occurred_at\": \"2026-07-23T03:00:00Z\", \"confidence\": " + confidence + "}";
    }

    @Test
    void list_excludes_other_users_events() throws Exception {
        makeEvent(other);
        FallEvent mine = makeEvent(guardian);
        mockMvc.perform(authed(get("/api/falls/"), guardian))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.length()").value(1))
            .andExpect(jsonPath("$[0].id").value(mine.getId()));
    }

    @Test
    void list_is_newest_first() throws Exception {
        FallEvent first = makeEvent(guardian, "안방", 1);
        FallEvent second = makeEvent(guardian, "안방", 2);
        mockMvc.perform(authed(get("/api/falls/"), guardian))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$[0].id").value(second.getId()))
            .andExpect(jsonPath("$[1].id").value(first.getId()));
    }

    @Test
    void post_forces_guardian_to_requester() throws Exception {
        // 클라이언트가 body에 남의 guardian id를 실어도 무시되어야 한다
        String body = mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"room_name\": \"부엌\", \"room_number\": 2, "
                    + "\"occurred_at\": \"2026-07-23T03:00:00Z\", \"confidence\": 0.88, "
                    + "\"guardian\": " + other.getId() + "}"))
            .andExpect(status().isCreated())
            .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        long id = ((Number) JsonPath.read(body, "$.id")).longValue();
        assertThat(fallEventRepository.findById(id).orElseThrow().getGuardian().getId())
            .isEqualTo(guardian.getId());
    }

    @Test
    void acknowledge_other_users_event_404() throws Exception {
        FallEvent theirs = makeEvent(other);
        mockMvc.perform(authed(post("/api/falls/" + theirs.getId() + "/acknowledge/"), guardian))
            .andExpect(status().isNotFound());
    }

    @Test
    void acknowledge_is_idempotent() throws Exception {
        FallEvent event = makeEvent(guardian);
        String url = "/api/falls/" + event.getId() + "/acknowledge/";

        String first = JsonPath.read(
            mockMvc.perform(authed(post(url), guardian))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8),
            "$.acknowledged_at");
        assertThat(first).isNotNull();

        String second = JsonPath.read(
            mockMvc.perform(authed(post(url), guardian))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8),
            "$.acknowledged_at");
        assertThat(second).isEqualTo(first);   // 두 번째 호출이 시각을 덮어쓰면 안 된다
    }

    @Test
    void duplicate_post_returns_200_and_no_new_row() throws Exception {
        String body = mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON).content(fallPayload("0.9")))
            .andExpect(status().isCreated())
            // 직렬화 계약 — UTC ISO-8601 Z 표기 왕복 확인
            .andExpect(jsonPath("$.occurred_at").value("2026-07-23T03:00:00Z"))
            .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        int firstId = JsonPath.read(body, "$.id");

        mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON).content(fallPayload("0.5")))
            .andExpect(status().isOk())               // 중복은 에러가 아니라 200 정상 경로다
            .andExpect(jsonPath("$.id").value(firstId))
            .andExpect(jsonPath("$.confidence").value(0.9));   // 기존 행이 그대로여야 한다
        assertThat(fallEventRepository.count()).isEqualTo(1);
    }

    @Test
    void created_post_sends_push_once() throws Exception {
        String body = mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON).content(fallPayload("0.9")))
            .andExpect(status().isCreated())
            .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        long id = ((Number) JsonPath.read(body, "$.id")).longValue();

        ArgumentCaptor<FallEvent> captor = ArgumentCaptor.forClass(FallEvent.class);
        verify(pushService, times(1)).sendToGuardianAsync(captor.capture());
        assertThat(captor.getValue().getId()).isEqualTo(id);
    }

    @Test
    void duplicate_post_sends_no_push() throws Exception {
        mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON).content(fallPayload("0.9")))
            .andExpect(status().isCreated());
        clearInvocations(pushService);

        mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON).content(fallPayload("0.9")))
            .andExpect(status().isOk());
        verify(pushService, never()).sendToGuardianAsync(any());
    }

    @Test
    void post_accepts_offset_and_stores_utc() throws Exception {
        // 스펙 5절 — 입력은 +09:00 오프셋도 받아 UTC로 변환 저장한다
        mockMvc.perform(authed(post("/api/falls/"), guardian)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"room_name\": \"안방\", \"room_number\": 1, "
                    + "\"occurred_at\": \"2026-07-23T12:00:00+09:00\", \"confidence\": 0.9}"))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.occurred_at").value("2026-07-23T03:00:00Z"));
    }
}
```

`backend/src/test/java/com/weniv/falls/AuthApiTest.java`의 `signup_returns_token_and_logs_in`을 원본 pytest 형태로 완성한다 (기존 메서드를 아래로 교체 — "Task 7에서 추가" 주석 제거):

```java
    @Test
    void signup_returns_token_and_logs_in() throws Exception {
        String body = mockMvc.perform(post("/api/auth/signup/").contentType(MediaType.APPLICATION_JSON)
                .content("{\"username\": \"new1\", \"password\": \"tough-pass-9x\"}"))
            .andExpect(status().isCreated())
            .andReturn().getResponse().getContentAsString(java.nio.charset.StandardCharsets.UTF_8);
        String token = com.jayway.jsonpath.JsonPath.read(body, "$.token");

        // 발급된 토큰이 곧바로 유효해야 한다 — 별도 로그인 없이 보호 API 접근
        mockMvc.perform(get("/api/falls/").header("Authorization", "Token " + token))
            .andExpect(status().isOk());
    }
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd backend && ./gradlew test --tests "com.weniv.falls.FallApiTest" --tests "com.weniv.falls.AuthApiTest"`
Expected: FAIL — FallController 미존재로 404 (AuthApiTest의 확장된 signup 테스트도 falls GET에서 404).

- [ ] **Step 3: DTO + FallService + FallController 구현**

`backend/src/main/java/com/weniv/falls/dto/FallEventRequest.java` (새 파일):

```java
// 낙상 등록 요청 — occurred_at은 오프셋 입력을 받기 위해 OffsetDateTime (저장은 UTC Instant)
package com.weniv.falls.dto;

import java.time.OffsetDateTime;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

// body의 guardian 등 잉여 필드는 무시한다 — 요청자로 강제되므로 클라이언트가 건드릴 수 없다
@JsonIgnoreProperties(ignoreUnknown = true)
public record FallEventRequest(
    @JsonProperty("room_name")
    @NotBlank(message = "이 필드는 필수 항목입니다.")
    @Size(max = 20, message = "이 필드의 글자 수가 20 이하인지 확인하십시오.")
    String roomName,

    @JsonProperty("room_number")
    @NotNull(message = "이 필드는 필수 항목입니다.")
    @Min(value = 0, message = "이 값이 0보다 크거나 같은지 확인하십시오.")
    @Max(value = 32767, message = "이 값이 32767보다 작거나 같은지 확인하십시오.")
    Integer roomNumber,

    @JsonProperty("occurred_at")
    @NotNull(message = "이 필드는 필수 항목입니다.")
    OffsetDateTime occurredAt,

    @NotNull(message = "이 필드는 필수 항목입니다.")
    Double confidence) {
}
```

`backend/src/main/java/com/weniv/falls/dto/FallEventResponse.java` (새 파일):

```java
// 낙상 응답 — snake_case 고정, 시각은 Instant가 ISO-8601 Z로 직렬화된다
package com.weniv.falls.dto;

import java.time.Instant;
import com.fasterxml.jackson.annotation.JsonProperty;

import com.weniv.falls.domain.FallEvent;

public record FallEventResponse(
    Long id,
    @JsonProperty("room_name") String roomName,
    @JsonProperty("room_number") Integer roomNumber,
    @JsonProperty("occurred_at") Instant occurredAt,
    @JsonProperty("created_at") Instant createdAt,
    Double confidence,
    @JsonProperty("acknowledged_at") Instant acknowledgedAt) {

    public static FallEventResponse from(FallEvent event) {
        return new FallEventResponse(event.getId(), event.getRoomName(), event.getRoomNumber(),
            event.getOccurredAt(), event.getCreatedAt(), event.getConfidence(),
            event.getAcknowledgedAt());
    }
}
```

`backend/src/main/java/com/weniv/falls/service/FallService.java` (새 파일):

```java
// 낙상 등록·조회·확인 — 오프라인 큐 재전송 멱등성 (같은 낙상 재수신 → 기존 행, 푸시 없음)
// 클래스 @Transactional을 쓰지 않는다: 제약 위반 후 재조회가 새 트랜잭션이어야 하기 때문 (Django autocommit 등가)
package com.weniv.falls.service;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;

import com.weniv.falls.domain.FallEvent;
import com.weniv.falls.domain.Guardian;
import com.weniv.falls.dto.FallEventRequest;
import com.weniv.falls.error.NotFoundException;
import com.weniv.falls.repository.FallEventRepository;

@Service
public class FallService {

    public record CreateResult(FallEvent event, boolean created) {}

    private final FallEventRepository fallEventRepository;

    public FallService(FallEventRepository fallEventRepository) {
        this.fallEventRepository = fallEventRepository;
    }

    public List<FallEvent> list(Guardian guardian) {
        // 남의 이벤트가 절대 새어나가지 않도록 요청자로 필터링한다
        return fallEventRepository.findByGuardianIdOrderByIdDesc(guardian.getId());
    }

    public CreateResult create(Guardian guardian, FallEventRequest request) {
        Instant occurredAt = request.occurredAt().toInstant();   // 오프셋 입력 → UTC 변환 저장

        Optional<FallEvent> existing = findDuplicate(guardian, request, occurredAt);
        if (existing.isPresent()) {
            return new CreateResult(existing.get(), false);   // 재전송 — 기존 행을 돌려주고 푸시 없음
        }
        try {
            FallEvent saved = fallEventRepository.saveAndFlush(new FallEvent(
                guardian, request.roomName(), request.roomNumber(), occurredAt,
                request.confidence()));
            return new CreateResult(saved, true);
        } catch (DataIntegrityViolationException e) {
            // 생성 경합 — uniq_fall_dedup에 걸렸으면 재조회해 200 경로로
            return new CreateResult(findDuplicate(guardian, request, occurredAt).orElseThrow(), false);
        }
    }

    public FallEvent acknowledge(Guardian guardian, Long id) {
        // guardian까지 걸어 조회 — 남의 이벤트는 존재 자체가 드러나지 않고 404가 된다
        FallEvent event = fallEventRepository.findByIdAndGuardianId(id, guardian.getId())
            .orElseThrow(NotFoundException::new);
        event.acknowledgeNow();   // 첫 확인 시각 보존 (멱등)
        return fallEventRepository.save(event);
    }

    private Optional<FallEvent> findDuplicate(Guardian guardian, FallEventRequest request,
                                              Instant occurredAt) {
        return fallEventRepository.findFirstByGuardianIdAndRoomNameAndRoomNumberAndOccurredAt(
            guardian.getId(), request.roomName(), request.roomNumber(), occurredAt);
    }
}
```

`backend/src/main/java/com/weniv/falls/controller/FallController.java` (새 파일):

```java
// 낙상 엔드포인트 — 신규 201 + 비동기 푸시 / 중복 200 + 푸시 없음
package com.weniv.falls.controller;

import java.util.List;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import com.weniv.falls.domain.Guardian;
import com.weniv.falls.dto.FallEventRequest;
import com.weniv.falls.dto.FallEventResponse;
import com.weniv.falls.service.FallService;
import com.weniv.falls.service.PushService;

@RestController
public class FallController {

    private final FallService fallService;
    private final PushService pushService;

    public FallController(FallService fallService, PushService pushService) {
        this.fallService = fallService;
        this.pushService = pushService;
    }

    @GetMapping("/api/falls/")
    public List<FallEventResponse> list(@AuthenticationPrincipal Guardian guardian) {
        return fallService.list(guardian).stream().map(FallEventResponse::from).toList();
    }

    @PostMapping("/api/falls/")
    public ResponseEntity<FallEventResponse> create(@AuthenticationPrincipal Guardian guardian,
                                                    @Valid @RequestBody FallEventRequest request) {
        FallService.CreateResult result = fallService.create(guardian, request);
        if (result.created()) {
            pushService.sendToGuardianAsync(result.event());   // 201일 때만 발송
        }
        return ResponseEntity.status(result.created() ? HttpStatus.CREATED : HttpStatus.OK)
            .body(FallEventResponse.from(result.event()));
    }

    @PostMapping("/api/falls/{id}/acknowledge/")
    public FallEventResponse acknowledge(@AuthenticationPrincipal Guardian guardian,
                                         @PathVariable Long id) {
        return FallEventResponse.from(fallService.acknowledge(guardian, id));
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd backend && ./gradlew test`
Expected: BUILD SUCCESSFUL — FallApiTest 9개 포함 전체 36개 통과.

`post_accepts_offset_and_stores_utc` 또는 `duplicate_post_returns_200_and_no_new_row`의 `occurred_at` 검증이 실패하면(예: `"2026-07-23T03:00:00.000Z"`처럼 다르게 직렬화) Jackson의 Instant 직렬화 설정 문제다 — 이때는 `FallEventResponse`의 시각 필드에 `@JsonFormat(shape = JsonFormat.Shape.STRING)`을 명시하거나 application.yml의 Jackson 날짜 설정을 조정해 `Z` 표기 ISO 문자열이 나오게 맞춘다(클라이언트 파서는 소수 초를 수용하므로 소수 초 유무는 무관, epoch 숫자만 아니면 된다).

- [ ] **Step 5: 커밋**

```bash
git add backend/src/main/java/com/weniv/falls backend/src/test/java/com/weniv/falls
git commit -m "feat: 낙상 API — 멱등 POST·acknowledge·201에만 비동기 푸시

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: 통합 검증 — 서버 36·웹 20·앱 4·E2E 2종

스펙 9절의 성공 기준 세 겹을 실제로 돌린다. 코드 수정이 없어야 정상이고, 실패가 나오면 **서버 쪽만** 고친다(클라이언트 무수정 원칙). 여기서 고친 게 있으면 해당 태스크 성격의 fix 커밋을 별도로 만든다.

**Files:**
- Modify: `context-notes.md` (검증 결과 기록)

**Interfaces:**
- Consumes: Task 1~7 전체
- Produces: 검증 통과 기록 — Task 9(Django 삭제)의 전제 조건

- [ ] **Step 1: 서버 테스트 전체 + 개수 확인**

```bash
cd backend && ./gradlew test && python3 - <<'EOF'
import glob, xml.etree.ElementTree as ET
files = glob.glob("build/test-results/test/*.xml")
total = sum(int(ET.parse(f).getroot().get("tests")) for f in files)
fails = sum(int(ET.parse(f).getroot().get("failures")) + int(ET.parse(f).getroot().get("errors")) for f in files)
print(f"tests={total} failures+errors={fails}")
EOF
```

Expected: `tests=36 failures+errors=0`

- [ ] **Step 2: 클라이언트 회귀 (무수정 확인 포함)**

```bash
git status --porcelain web/ app/    # 출력이 비어야 한다 (web/showcase.html 제외 — 이 라운드 이전부터 untracked)
cd web && npm test                  # Expected: Tests  20 passed (20)
cd ../app && flutter test           # Expected: All tests passed! (4개)
```

- [ ] **Step 3: E2E 준비 — VAPID 키 생성 + 서버 3종 기동**

```bash
npx web-push generate-vapid-keys    # Private Key를 복사한다 (Public Key는 서버가 파생하므로 불필요)
cd scripts/e2e && npm install       # playwright-core 준비 (최초 1회)
```

터미널(백그라운드) 2개를 띄운다.

```bash
# 1) 백엔드 — 푸시 E2E용 VAPID 환경변수 포함
cd backend && VAPID_PRIVATE_KEY=<위에서 복사한 키> VAPID_SUBJECT=mailto:test@example.com ./gradlew bootRun
# 2) 정적 서버
cd web && npx serve -l 5500 .
```

기동 확인: `curl -s http://127.0.0.1:8000/` → `{"status":"ok",...}`.

- [ ] **Step 4: E2E 2종 실행**

```bash
cd scripts/e2e
node queue-e2e.mjs    # Expected: "큐 재전송 E2E 전부 통과" (exit 0)
node push-e2e.mjs     # Expected: "웹 푸시 E2E 전부 통과" (exit 0. 헤드리스 수신 불가 시 --headed로 재시도)
```

큐 E2E는 밀리초 단위 `occurred_at` 왕복 일치(`new Date(f.occurred_at).getTime()`)와 중복 재전송 200 흡수를, 푸시 E2E는 실제 Chrome 구독→발송→서비스 워커 알림(`"부엌 3에서 낙상 감지"`)까지 검증한다. 실행 후 두 백그라운드 프로세스를 종료한다.

- [ ] **Step 5: 검증 기록 + 커밋**

`context-notes.md` 끝에 결정 기록을 추가한다 — 실제 Spring Boot 버전, Jackson 세대, web-push 라이브러리 상태 확인 결과, 테스트 4종(36·20·4·E2E 2종) 결과, 발견한 특이사항.

```bash
git add context-notes.md
git commit -m "docs: Spring 교체 검증 기록 — 서버 36·웹 20·앱 4·E2E 2종 통과

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: Django 제거 + 문서 갱신

검증이 끝났으니 옛 백엔드를 지운다(git 히스토리에는 남는다). README를 Spring Boot + PostgreSQL 기준으로 고치고, Django 코드 설명 문서를 제거한다.

**Files:**
- Delete (tracked): `backend/manage.py`, `backend/pytest.ini`, `backend/requirements.txt`, `backend/config/`, `backend/falls/`, `docs/backend-architecture.html`
- Delete (untracked): `backend/.venv/`, `backend/db.sqlite3`, `backend/.pytest_cache/`, `backend/.DS_Store`, `backend/falls/.DS_Store`, `backend/config/.DS_Store`
- Modify: `README.md`, `.gitignore`

**Interfaces:**
- Consumes: Task 8의 통과 기록 (삭제 전제 조건)
- Produces: 최종 리포 상태 — Spring 백엔드 단독

- [ ] **Step 1: Django 파일 삭제**

```bash
cd /Users/munhokang/82107/weniv_project
git rm -r backend/manage.py backend/pytest.ini backend/requirements.txt backend/config backend/falls
git rm docs/backend-architecture.html
rm -rf backend/.venv backend/db.sqlite3 backend/.pytest_cache backend/.DS_Store
ls backend    # Expected: build.gradle, settings.gradle, gradlew, gradle, src, .gitignore만 남는다
```

- [ ] **Step 2: .gitignore에서 Python 항목 제거**

`.gitignore`의 Python/Django 블록(`__pycache__/`, `*.py[cod]`, `.venv/`, `venv/`, `db.sqlite3`, `.pytest_cache/`, `staticfiles/`)을 삭제한다 — 이 변경으로 참조 대상이 사라져 고아가 된 항목들이다. Node·Flutter·`.superpowers/` 블록은 유지한다.

- [ ] **Step 3: README 갱신**

`README.md`에서 다음을 바꾼다. (섹션 구조·감지 알고리즘·알려진 한계는 그대로 둔다.)

1. **구조도** — `[Django + SQLite]  (backend/)` 줄을 `[Spring Boot + PostgreSQL]  (backend/)`로 교체.

2. **실행 방법 1번 섹션** — `### 1. Django (:8000)` 전체를 다음으로 교체 (admin·createsuperuser는 Spring 버전에 없다 — 스펙 범위 밖):

````markdown
### 1. Spring Boot (`:8000`)

```bash
cd backend
createdb fall_detection        # 최초 1회 (postgresql@18 서비스는 이미 실행 중)
./gradlew bootRun              # 0.0.0.0:8000 — 같은 와이파이 기기의 접속을 받는다
```
````

3. **푸시 알림 섹션의 키 생성 스니펫** — Python heredoc 블록을 다음으로 교체:

````markdown
웹 푸시 키는 한 번만 만들면 된다. 공개키는 서버가 개인키에서 계산하므로 따로 없다.

```bash
npx web-push generate-vapid-keys   # 출력의 Private Key가 VAPID_PRIVATE_KEY다
```
````

4. **푸시 실행 커맨드** — `.venv/bin/python manage.py runserver` 줄을 교체:

````markdown
```bash
cd backend && VAPID_PRIVATE_KEY=<키> VAPID_SUBJECT=mailto:<본인이메일> ./gradlew bootRun
```
````

5. **테스트 섹션** — 백엔드 줄을 교체:

````markdown
```bash
cd backend && ./gradlew test    # 36개 — 인증·소유권·방·프로필·푸시·전송 멱등성 (fall_detection_test DB 필요: createdb fall_detection_test)
cd web     && npm test          # 20개 — 상태머신 시나리오 + 오프라인 큐
cd app     && flutter test      # 4개 — 새 이벤트 판별
```
````

6. **문서 섹션** — `- [백엔드 구현 설명](docs/backend-architecture.html)` 줄 삭제, 아래 두 줄 추가:

```markdown
- [설계 — 백엔드 Spring Boot 교체 (2026-07-24)](docs/superpowers/specs/2026-07-24-spring-boot-backend-design.md)
- [구현 계획 — 백엔드 Spring Boot 교체 (2026-07-25)](docs/superpowers/plans/2026-07-25-spring-boot-backend.md)
```

7. **잔여 "Django" 단어 교체** — 푸시 알림 섹션의 "아래 환경변수를 붙여 Django를 실행하면"을 "아래 환경변수를 붙여 백엔드를 실행하면"으로, 그 외 README 본문에 남은 Django 언급을 같은 요령으로 바꾼다. 단 `web/`·`app/` 소스 안의 "Django" 주석은 클라이언트 무수정 원칙에 따라 그대로 둔다.

- [ ] **Step 4: 최종 검증**

```bash
cd backend && ./gradlew test    # Expected: BUILD SUCCESSFUL, 36개 (Django 삭제가 빌드에 영향 없음을 확인)
cd .. && git status             # Expected: 삭제·수정 파일만 스테이징 대상, backend/에 잔여물 없음
grep -n "Django\|backend-architecture\|manage.py\|runserver" README.md    # Expected: 출력 없음
```

- [ ] **Step 5: 커밋**

```bash
git add -u
git add README.md .gitignore
git commit -m "refactor: Django 백엔드 제거 — Spring Boot + PostgreSQL 교체 완료, 문서 갱신

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## 실행 노트

- **워크트리** — 실행 시 `superpowers:using-git-worktrees`로 격리 워크스페이스를 만든다. 이 리포에서 검증된 함정 2개(메모리 기록): ① 계획·브리프의 절대 경로(`/Users/munhokang/82107/weniv_project/...`)는 워크트리 경로로 치환해서 읽을 것, ② 워크트리는 원격이 아니라 **로컬 HEAD 기준**으로 만들 것. 단, 이 계획의 Task 1(createdb)·Task 8(E2E)은 DB·포트 8000·5500을 쓰므로 동시에 다른 서버를 띄우지 않는다.
- **Django venv 의존** — Task 3 Step 1이 `backend/.venv` 안의 Django 파일을 읽는다. venv가 없으면 `python3 -m venv .venv && .venv/bin/pip install -r requirements.txt`로 복원한 뒤 추출한다(requirements.txt는 Task 9까지 남아 있다).
- **컨텍스트 노트** — 각 태스크에서 계획과 다르게 결정한 것(라이브러리 API 차이, Jackson 세대, Boot 버전 등)은 그때그때 `context-notes.md`에 적는다. Task 8에 정식 기록 스텝이 있다.
- **테스트 개수 기준** — 서버 36(JUnit)·웹 20(vitest)·앱 4(flutter). pytest 32개와의 대응은 문서 상단 대응표가 정본이다.






