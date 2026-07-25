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
