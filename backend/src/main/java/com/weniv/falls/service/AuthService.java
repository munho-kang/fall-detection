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
