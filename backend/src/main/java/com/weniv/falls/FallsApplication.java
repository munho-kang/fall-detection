// 낙상 감지 백엔드 진입점 — Spring Boot 애플리케이션
package com.weniv.falls;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class FallsApplication {

	public static void main(String[] args) {
		SpringApplication.run(FallsApplication.class, args);
	}

}
