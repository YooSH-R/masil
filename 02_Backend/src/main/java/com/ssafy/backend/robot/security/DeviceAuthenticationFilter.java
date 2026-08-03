package com.ssafy.backend.robot.security;

import com.ssafy.backend.auth.service.TokenHashService;
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

    private final JdbcTemplate jdbcTemplate;
    private final TokenHashService tokenHashService;

    public DeviceAuthenticationFilter(
            JdbcTemplate jdbcTemplate,
            TokenHashService tokenHashService
    ) {
        this.jdbcTemplate = jdbcTemplate;
        this.tokenHashService = tokenHashService;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !DEVICE_IMAGE_PATH.matcher(request.getServletPath()).matches();
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain
    ) throws ServletException, IOException {
        Matcher matcher = DEVICE_IMAGE_PATH.matcher(request.getServletPath());
        String authorization = request.getHeader("Authorization");
        if (!matcher.matches()
                || authorization == null
                || !authorization.startsWith("Device ")) {
            response.sendError(HttpServletResponse.SC_UNAUTHORIZED);
            return;
        }

        String deviceId = matcher.group(1);
        String tokenHash = tokenHashService.hash(authorization.substring(7));
        List<Long> matched = jdbcTemplate.query("""
                SELECT r.id
                FROM robots r
                JOIN robot_credentials c ON c.robot_id = r.id
                WHERE r.serial_number = ?
                  AND c.device_token_hash = ?
                  AND (
                    c.device_token_expires_at IS NULL
                    OR c.device_token_expires_at > CURRENT_TIMESTAMP
                  )
                """,
                (rs, rowNum) -> rs.getLong(1),
                deviceId,
                tokenHash
        );
        if (matched.size() != 1) {
            response.sendError(HttpServletResponse.SC_UNAUTHORIZED);
            return;
        }

        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(
                        new DevicePrincipal(deviceId),
                        null,
                        List.of(
                                new SimpleGrantedAuthority("ROLE_DEVICE")
                        )
                )
        );
        filterChain.doFilter(request, response);
    }

    public record DevicePrincipal(String deviceId) {
    }
}
