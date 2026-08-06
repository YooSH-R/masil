package com.ssafy.backend.walk.diary;

import com.ssafy.backend.common.error.BusinessException;
import com.ssafy.backend.common.error.ErrorCode;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.exception.SdkClientException;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Response;
import software.amazon.awssdk.services.s3.model.S3Exception;
import software.amazon.awssdk.services.s3.model.S3Object;
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
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.function.Consumer;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@Service
@ConditionalOnProperty(name = "storage.s3.enabled", havingValue = "true")
public class WalkDiaryService {

    private static final Logger log = LoggerFactory.getLogger(
            WalkDiaryService.class
    );

    private static final String IMAGE_FILE = "story_image.png";
    private static final String MARKDOWN_FILE = "walk_log.md";
    private static final Pattern DIARY_OBJECT = Pattern.compile(
            "^(\\d{4}-\\d{2}-\\d{2})/session([1-6])/"
                    + "(story_image\\.png|walk_log\\.md)$"
    );

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

    public DiaryDetail getDiary(
            long userId,
            String deviceId,
            LocalDate walkDate,
            int session
    ) {
        WalkDiaryStore.OwnedDevice ownedDevice = store
                .findActiveOwnedDevice(userId, deviceId)
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.WALK_DIARY_NOT_FOUND
                ));
        String objectPrefix = objectPrefix(deviceId, walkDate, session);
        String imageKey = objectPrefix + IMAGE_FILE;
        String markdownKey = objectPrefix + MARKDOWN_FILE;

        try {
            requireCompleteDiary(ownedDevice, objectPrefix);
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
                    deviceId,
                    walkDate,
                    session,
                    imageUrl,
                    expiresAt,
                    markdown
            );
        } catch (S3Exception exception) {
            log.warn(
                    "S3 산책일지 상세 조회 실패: bucket={}, prefix={}",
                    properties.bucket(),
                    objectPrefix,
                    exception
            );
            if (exception.statusCode() == 404) {
                throw new BusinessException(ErrorCode.WALK_DIARY_NOT_FOUND);
            }
            throw storageUnavailable();
        } catch (SdkClientException exception) {
            log.warn(
                    "S3 산책일지 상세 연결 실패: bucket={}, prefix={}",
                    properties.bucket(),
                    objectPrefix,
                    exception
            );
            throw storageUnavailable();
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

        try {
            Map<LocalDate, List<DiarySummary>> grouped = new TreeMap<>(
                    Comparator.reverseOrder()
            );
            for (WalkDiaryStore.OwnedDevice device
                    : store.findActiveOwnedDevices(userId)) {
                for (DiaryReference diary : listCompleteDiaries(device)) {
                    if (beforeDate != null
                            && !diary.walkDate().isBefore(beforeDate)) {
                        continue;
                    }
                    grouped.computeIfAbsent(
                            diary.walkDate(),
                            ignored -> new ArrayList<>()
                    ).add(new DiarySummary(
                            device.deviceId(),
                            diary.session()
                    ));
                }
            }
            grouped.values().forEach(diaries -> diaries.sort(
                    Comparator.comparing(DiarySummary::deviceId)
                            .thenComparingInt(DiarySummary::session)
            ));

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
        } catch (S3Exception | SdkClientException exception) {
            log.warn(
                    "S3 산책일지 피드 조회 실패: bucket={}",
                    properties.bucket(),
                    exception
            );
            throw storageUnavailable();
        }
    }

    private List<DiaryReference> listCompleteDiaries(
            WalkDiaryStore.OwnedDevice device
    ) {
        String prefix = devicePrefix(device.deviceId());
        Map<DiaryReference, Set<String>> filesByDiary = new HashMap<>();
        listObjects(prefix, object -> collectDiaryObject(
                device,
                prefix,
                object,
                filesByDiary
        ));

        return filesByDiary.entrySet().stream()
                .filter(entry -> entry.getValue().contains(IMAGE_FILE)
                        && entry.getValue().contains(MARKDOWN_FILE))
                .map(Map.Entry::getKey)
                .sorted(Comparator.comparing(DiaryReference::walkDate)
                        .reversed()
                        .thenComparingInt(DiaryReference::session))
                .toList();
    }

    private void requireCompleteDiary(
            WalkDiaryStore.OwnedDevice device,
            String objectPrefix
    ) {
        Set<String> files = new HashSet<>();
        listObjects(objectPrefix, object -> {
            if (!belongsToCurrentPairing(device, object)) {
                return;
            }
            if (object.key().equals(objectPrefix + IMAGE_FILE)) {
                files.add(IMAGE_FILE);
            } else if (object.key().equals(objectPrefix + MARKDOWN_FILE)) {
                files.add(MARKDOWN_FILE);
            }
        });
        if (!files.contains(IMAGE_FILE) || !files.contains(MARKDOWN_FILE)) {
            throw new BusinessException(ErrorCode.WALK_DIARY_NOT_FOUND);
        }
    }

    private void listObjects(String prefix, Consumer<S3Object> consumer) {
        String continuationToken = null;
        do {
            ListObjectsV2Request.Builder request = ListObjectsV2Request.builder()
                    .bucket(properties.bucket())
                    .prefix(prefix);
            if (continuationToken != null) {
                request.continuationToken(continuationToken);
            }
            ListObjectsV2Response response = s3Client.listObjectsV2(
                    request.build()
            );
            response.contents().forEach(consumer);
            continuationToken = Boolean.TRUE.equals(response.isTruncated())
                    ? response.nextContinuationToken()
                    : null;
            if (Boolean.TRUE.equals(response.isTruncated())
                    && (continuationToken == null
                    || continuationToken.isBlank())) {
                throw SdkClientException.create(
                        "S3 목록 응답에 continuation token이 없습니다."
                );
            }
        } while (continuationToken != null);
    }

    private void collectDiaryObject(
            WalkDiaryStore.OwnedDevice device,
            String prefix,
            S3Object object,
            Map<DiaryReference, Set<String>> filesByDiary
    ) {
        if (!belongsToCurrentPairing(device, object)) {
            return;
        }
        String key = object.key();
        if (!key.startsWith(prefix)) {
            return;
        }
        Matcher matcher = DIARY_OBJECT.matcher(key.substring(prefix.length()));
        if (!matcher.matches()) {
            return;
        }
        try {
            DiaryReference diary = new DiaryReference(
                    LocalDate.parse(matcher.group(1)),
                    Integer.parseInt(matcher.group(2))
            );
            filesByDiary.computeIfAbsent(
                    diary,
                    ignored -> new HashSet<>()
            ).add(matcher.group(3));
        } catch (DateTimeParseException ignored) {
            // 정해진 yyyy-MM-dd 경로 규칙을 벗어난 객체는 피드에서 제외한다.
        }
    }

    private boolean belongsToCurrentPairing(
            WalkDiaryStore.OwnedDevice device,
            S3Object object
    ) {
        return object.lastModified() != null
                && !object.lastModified().isBefore(device.visibleFrom());
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
            throw storageUnavailable();
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

    private String devicePrefix(String deviceId) {
        return "robot-images/" + deviceId + "/";
    }

    private String objectPrefix(
            String deviceId,
            LocalDate walkDate,
            int session
    ) {
        return devicePrefix(deviceId) + walkDate + "/session" + session + "/";
    }

    private BusinessException storageUnavailable() {
        return new BusinessException(ErrorCode.WALK_DIARY_STORAGE_UNAVAILABLE);
    }

    public record DiaryDetail(
            String deviceId,
            LocalDate walkDate,
            int session,
            String imageUrl,
            Instant imageUrlExpiresAt,
            String markdown
    ) {
    }

    public record DiaryDay(
            LocalDate walkDate,
            int walkCount,
            List<DiarySummary> diaries
    ) {
    }

    public record DiaryFeed(
            List<DiaryDay> items,
            LocalDate nextCursor,
            boolean hasNext
    ) {
    }

    public record DiarySummary(String deviceId, int session) {
    }

    private record DiaryReference(LocalDate walkDate, int session) {
    }
}
