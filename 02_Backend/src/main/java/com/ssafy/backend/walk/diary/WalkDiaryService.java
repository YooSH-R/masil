package com.ssafy.backend.walk.diary;

import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.exception.SdkClientException;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.HeadObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Exception;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Service
@ConditionalOnProperty(name = "storage.s3.enabled", havingValue = "true")
public class WalkDiaryService {

    private static final String IMAGE_FILE = "story_image.png";
    private static final String MARKDOWN_FILE = "walk_log.md";

    private final WalkDiaryStore store;
    private final S3Client s3Client;
    private final S3Presigner presigner;
    private final WalkDiaryS3Properties properties;

    public WalkDiaryService(
            WalkDiaryStore store,
            S3Client s3Client,
            S3Presigner presigner,
            WalkDiaryS3Properties properties
    ) {
        this.store = store;
        this.s3Client = s3Client;
        this.presigner = presigner;
        this.properties = properties;
    }

    public DiaryDetail getDiary(long userId, long walkId) {
        WalkDiaryStore.StoredDiary diary = store
                .findOwnedDiary(userId, walkId)
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.WALK_DIARY_NOT_FOUND
                ));
        String imageKey = diary.objectPrefix() + IMAGE_FILE;
        String markdownKey = diary.objectPrefix() + MARKDOWN_FILE;

        try {
            s3Client.headObject(HeadObjectRequest.builder()
                    .bucket(properties.bucket())
                    .key(imageKey)
                    .build());
            String markdown = readMarkdown(markdownKey);
            Instant expiresAt = Instant.now().plusSeconds(
                    properties.presignDurationSeconds()
            );
            String imageUrl = presigner.presignGetObject(
                    GetObjectPresignRequest.builder()
                            .signatureDuration(Duration.ofSeconds(
                                    properties.presignDurationSeconds()
                            ))
                            .getObjectRequest(GetObjectRequest.builder()
                                    .bucket(properties.bucket())
                                    .key(imageKey)
                                    .build())
                            .build()
            ).url().toString();

            return new DiaryDetail(
                    diary.walkId(),
                    diary.deviceId(),
                    diary.walkDate(),
                    diary.session(),
                    diary.startedAt(),
                    diary.endedAt(),
                    imageUrl,
                    expiresAt,
                    markdown
            );
        } catch (S3Exception exception) {
            if (exception.statusCode() == 404) {
                throw new BusinessException(ErrorCode.WALK_DIARY_NOT_FOUND);
            }
            throw new BusinessException(
                    ErrorCode.WALK_DIARY_STORAGE_UNAVAILABLE
            );
        } catch (SdkClientException exception) {
            throw new BusinessException(
                    ErrorCode.WALK_DIARY_STORAGE_UNAVAILABLE
            );
        }
    }

    private String readMarkdown(String markdownKey) {
        GetObjectRequest request = GetObjectRequest.builder()
                .bucket(properties.bucket())
                .key(markdownKey)
                .build();
        int readLimit = Math.toIntExact(properties.maxMarkdownBytes() + 1);
        try (ResponseInputStream<GetObjectResponse> input =
                     s3Client.getObject(request)) {
            Long contentLength = input.response().contentLength();
            if (contentLength == null
                    || contentLength < 0
                    || contentLength > properties.maxMarkdownBytes()) {
                throw new BusinessException(
                        ErrorCode.WALK_DIARY_CONTENT_INVALID
                );
            }
            byte[] content = input.readNBytes(readLimit);
            if (content.length > properties.maxMarkdownBytes()) {
                throw new BusinessException(
                        ErrorCode.WALK_DIARY_CONTENT_INVALID
                );
            }
            return decodeUtf8(content);
        } catch (IOException exception) {
            throw new BusinessException(
                    ErrorCode.WALK_DIARY_STORAGE_UNAVAILABLE
            );
        }
    }

    private String decodeUtf8(byte[] content) {
        try {
            return StandardCharsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(content))
                    .toString();
        } catch (CharacterCodingException exception) {
            throw new BusinessException(ErrorCode.WALK_DIARY_CONTENT_INVALID);
        }
    }

    public DiaryFeed getFeed(
            long userId,
            LocalDate beforeDate,
            int size
    ) {
        if (size < 1 || size > 100) {
            throw new IllegalArgumentException(
                    "산책일지 피드 크기는 1에서 100 사이여야 합니다."
            );
        }
        Map<LocalDate, List<DiarySummary>> grouped = new LinkedHashMap<>();
        for (WalkDiaryStore.FeedRow diary : store.findOwnedDiaryFeed(
                userId,
                beforeDate,
                size + 1
        )) {
            grouped.computeIfAbsent(
                    diary.walkDate(),
                    ignored -> new ArrayList<>()
            ).add(new DiarySummary(
                    diary.walkId(),
                    diary.session(),
                    diary.startedAt(),
                    diary.endedAt()
            ));
        }
        boolean hasNext = grouped.size() > size;
        List<DiaryDay> items = grouped.entrySet().stream()
                .limit(size)
                .map(entry -> new DiaryDay(
                        entry.getKey(),
                        entry.getValue().size(),
                        List.copyOf(entry.getValue())
                ))
                .toList();
        LocalDate nextCursor = hasNext && !items.isEmpty()
                ? items.get(items.size() - 1).walkDate()
                : null;
        return new DiaryFeed(items, nextCursor, hasNext);
    }

    public record DiaryDetail(
            long walkId,
            String deviceId,
            LocalDate walkDate,
            int session,
            Instant startedAt,
            Instant endedAt,
            String imageUrl,
            Instant imageUrlExpiresAt,
            String markdown
    ) {
    }

    public record DiaryDay(
            LocalDate walkDate,
            int walkCount,
            List<DiarySummary> walks
    ) {
    }

    public record DiaryFeed(
            List<DiaryDay> items,
            LocalDate nextCursor,
            boolean hasNext
    ) {
    }

    public record DiarySummary(
            long walkId,
            int session,
            Instant startedAt,
            Instant endedAt
    ) {
    }
}
