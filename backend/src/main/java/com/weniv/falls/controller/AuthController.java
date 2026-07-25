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
