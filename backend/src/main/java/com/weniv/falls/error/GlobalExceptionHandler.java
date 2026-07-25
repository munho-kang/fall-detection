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
