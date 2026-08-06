package com.ssafy.backend.robot.security;

import com.ssafy.backend.auth.service.TokenHashService;
import com.ssafy.backend.common.error.ErrorCode;
import com.ssafy.backend.common.error.ErrorResponseWriter;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@Component
public class DeviceAuthenticationFilter extends OncePerRequestFilter {

    private static final Pattern DEVICE_IMAGE_PATH = Pattern.compile(
            "^/v1/devices/([^/]+)/images(?:/.*)?$"
    );
    private static final Pattern WALK_LIFECYCLE_PATH = Pattern.compile(
            "^/v1/walks/[^/]+/(?:start|end)$"
    );

    private final JdbcTemplate jdbcTemplate;
    private final TokenHashService tokenHashService;
    private final ErrorResponseWriter errorResponseWriter;

    public DeviceAuthenticationFilter(
            JdbcTemplate jdbcTemplate,
            TokenHashService tokenHashService,
            ErrorResponseWriter errorResponseWriter
    ) {
        this.jdbcTemplate = jdbcTemplate;
        this.tokenHashService = tokenHashService;
        this.errorResponseWriter = errorResponseWriter;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = requestPath(request);
        boolean imageRequest = DEVICE_IMAGE_PATH.matcher(path).matches();
        boolean walkLifecycleRequest = "POST".equals(request.getMethod())
                && WALK_LIFECYCLE_PATH.matcher(path).matches();
        return !imageRequest && !walkLifecycleRequest;
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain
    ) throws ServletException, IOException {
        Matcher imageMatcher = DEVICE_IMAGE_PATH.matcher(requestPath(request));
        String authorization = request.getHeader("Authorization");
        if (authorization == null
                || !authorization.startsWith("Device ")) {
            writeUnauthorized(request, response);
            return;
        }

        String token = authorization.substring(7);
        if (token.isBlank()) {
            writeUnauthorized(request, response);
            return;
        }

        List<DevicePrincipal> principals = jdbcTemplate.query("""
                SELECT r.id, r.serial_number
                FROM robots r
                JOIN robot_credentials c ON c.robot_id = r.id
                WHERE c.device_token_hash = ?
                  AND (
                    c.device_token_expires_at IS NULL
                    OR c.device_token_expires_at > CURRENT_TIMESTAMP
                  )
                """,
                (rs, rowNum) -> new DevicePrincipal(
                        rs.getLong("id"),
                        rs.getString("serial_number")
                ),
                tokenHashService.hash(token)
        );
        if (principals.size() != 1) {
            writeUnauthorized(request, response);
            return;
        }

        DevicePrincipal principal = principals.get(0);
        if (imageMatcher.matches()
                && !imageMatcher.group(1).equals(principal.deviceId())) {
            writeUnauthorized(request, response);
            return;
        }

        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(
                        principal,
                        null,
                        List.of(
                                new SimpleGrantedAuthority("ROLE_DEVICE")
                        )
                )
        );
        filterChain.doFilter(request, response);
    }

    private void writeUnauthorized(
            HttpServletRequest request,
            HttpServletResponse response
    ) throws IOException {
        SecurityContextHolder.clearContext();
        errorResponseWriter.write(
                request,
                response,
                ErrorCode.INVALID_DEVICE_TOKEN
        );
    }

    private String requestPath(HttpServletRequest request) {
        String path = request.getRequestURI();
        String contextPath = request.getContextPath();
        if (!contextPath.isEmpty() && path.startsWith(contextPath)) {
            return path.substring(contextPath.length());
        }
        return path;
    }
}
