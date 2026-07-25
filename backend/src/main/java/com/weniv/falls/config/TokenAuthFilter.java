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
