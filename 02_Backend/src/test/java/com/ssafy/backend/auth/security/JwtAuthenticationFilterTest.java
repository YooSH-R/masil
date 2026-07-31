package com.ssafy.backend.auth.security;

import com.ssafy.backend.auth.service.TokenService;
import jakarta.servlet.FilterChain;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class JwtAuthenticationFilterTest {

    @AfterEach
    void clearSecurityContext() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void storesTypedUserPrincipalWithUserRole() throws Exception {
        TokenService tokenService = mock(TokenService.class);
        JwtAuthenticationFilter filter =
                new JwtAuthenticationFilter(tokenService);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("Authorization", "Bearer access-token");
        MockHttpServletResponse response = new MockHttpServletResponse();
        FilterChain chain = mock(FilterChain.class);
        when(tokenService.parseAccessTokenPrincipal("access-token"))
                .thenReturn(
                        new TokenService.AccessTokenPrincipal(
                                7L,
                                "browser-001",
                                11L
                        )
                );

        filter.doFilter(request, response, chain);

        Authentication authentication =
                SecurityContextHolder.getContext().getAuthentication();
        UserPrincipal principal = assertInstanceOf(
                UserPrincipal.class,
                authentication.getPrincipal()
        );
        assertEquals(7L, principal.userId());
        assertEquals(
                "browser-001",
                request.getAttribute("authenticatedDeviceId")
        );
        assertEquals(
                11L,
                request.getAttribute("authenticatedSessionId")
        );
        assertTrue(authentication.getAuthorities().stream().anyMatch(
                authority -> authority.getAuthority().equals("ROLE_USER")
        ));
        verify(chain).doFilter(request, response);
    }
}
