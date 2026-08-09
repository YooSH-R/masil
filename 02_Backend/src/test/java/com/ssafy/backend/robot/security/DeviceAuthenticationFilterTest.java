package com.ssafy.backend.robot.security;

import com.ssafy.backend.auth.service.TokenHashService;
import com.ssafy.backend.common.error.ErrorCode;
import com.ssafy.backend.common.error.ErrorResponseWriter;
import jakarta.servlet.FilterChain;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class DeviceAuthenticationFilterTest {

    @AfterEach
    void clearSecurityContext() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void storesDevicePrincipalWithDeviceRole() throws Exception {
        JdbcTemplate jdbcTemplate = mock(JdbcTemplate.class);
        TokenHashService tokenHashService = mock(TokenHashService.class);
        ErrorResponseWriter errorResponseWriter = mock(ErrorResponseWriter.class);
        DeviceAuthenticationFilter filter =
                new DeviceAuthenticationFilter(
                        jdbcTemplate,
                        tokenHashService,
                        errorResponseWriter
                );
        MockHttpServletRequest request = new MockHttpServletRequest(
                "POST",
                "/v1/devices/device-001/images/presigned-url"
        );
        request.setServletPath(
                "/v1/devices/device-001/images/presigned-url"
        );
        request.addHeader("Authorization", "Device raw-token");
        MockHttpServletResponse response = new MockHttpServletResponse();
        FilterChain chain = mock(FilterChain.class);
        when(tokenHashService.hash("raw-token")).thenReturn("token-hash");
        when(jdbcTemplate.query(
                any(String.class),
                org.mockito.ArgumentMatchers.<RowMapper<DevicePrincipal>>any(),
                eq("token-hash")
        )).thenReturn(List.of(new DevicePrincipal(1L, "device-001")));

        filter.doFilter(request, response, chain);

        Authentication authentication =
                SecurityContextHolder.getContext().getAuthentication();
        DevicePrincipal principal =
                assertInstanceOf(
                        DevicePrincipal.class,
                        authentication.getPrincipal()
                );
        assertEquals(1L, principal.robotId());
        assertEquals("device-001", principal.deviceId());
        assertTrue(authentication.getAuthorities().stream().anyMatch(
                authority -> authority.getAuthority().equals("ROLE_DEVICE")
        ));
        verify(chain).doFilter(request, response);
    }

    @Test
    void authenticatesWalkLifecycleByDeviceTokenWithoutDeviceIdInPath()
            throws Exception {
        JdbcTemplate jdbcTemplate = mock(JdbcTemplate.class);
        TokenHashService tokenHashService = mock(TokenHashService.class);
        ErrorResponseWriter errorResponseWriter = mock(ErrorResponseWriter.class);
        DeviceAuthenticationFilter filter = new DeviceAuthenticationFilter(
                jdbcTemplate,
                tokenHashService,
                errorResponseWriter
        );
        MockHttpServletRequest request = new MockHttpServletRequest(
                "POST",
                "/api/v1/walks/41/start"
        );
        request.setContextPath("/api");
        request.addHeader("Authorization", "Device raw-token");
        MockHttpServletResponse response = new MockHttpServletResponse();
        FilterChain chain = mock(FilterChain.class);
        when(tokenHashService.hash("raw-token")).thenReturn("token-hash");
        when(jdbcTemplate.query(
                any(String.class),
                org.mockito.ArgumentMatchers.<RowMapper<DevicePrincipal>>any(),
                eq("token-hash")
        )).thenReturn(List.of(new DevicePrincipal(7L, "device-007")));

        filter.doFilter(request, response, chain);

        Authentication authentication =
                SecurityContextHolder.getContext().getAuthentication();
        DevicePrincipal principal = assertInstanceOf(
                DevicePrincipal.class,
                authentication.getPrincipal()
        );
        assertEquals(7L, principal.robotId());
        assertEquals("device-007", principal.deviceId());
        verify(chain).doFilter(request, response);
    }

    @Test
    void rejectsImageRequestWhenTokenBelongsToAnotherDevice()
            throws Exception {
        JdbcTemplate jdbcTemplate = mock(JdbcTemplate.class);
        TokenHashService tokenHashService = mock(TokenHashService.class);
        ErrorResponseWriter errorResponseWriter = mock(ErrorResponseWriter.class);
        DeviceAuthenticationFilter filter = new DeviceAuthenticationFilter(
                jdbcTemplate,
                tokenHashService,
                errorResponseWriter
        );
        MockHttpServletRequest request = new MockHttpServletRequest(
                "POST",
                "/v1/devices/device-001/images/presigned-url"
        );
        request.addHeader("Authorization", "Device raw-token");
        MockHttpServletResponse response = new MockHttpServletResponse();
        FilterChain chain = mock(FilterChain.class);
        when(tokenHashService.hash("raw-token")).thenReturn("token-hash");
        when(jdbcTemplate.query(
                any(String.class),
                org.mockito.ArgumentMatchers.<RowMapper<DevicePrincipal>>any(),
                eq("token-hash")
        )).thenReturn(List.of(new DevicePrincipal(2L, "device-002")));

        filter.doFilter(request, response, chain);

        verify(errorResponseWriter).write(
                request,
                response,
                ErrorCode.INVALID_DEVICE_TOKEN
        );
        verify(chain, never()).doFilter(request, response);
        assertTrue(SecurityContextHolder.getContext().getAuthentication() == null);
    }
}
