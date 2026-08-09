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

    private static final String MARKDOWN_FILE = "walk_log.md";

    /**
     * 세션 폴더에 바로 놓인 이미지 파일명.
     *
     * <p>한 세션에 {@code event_01.png ~ event_NN.png} 로 여러 장이 올라온다.
     * 예전 세션은 {@code story_image.png} 한 장뿐이라 둘 다 인정한다. 앵커가
     * 붙어 있어 {@code flow_panels/event_01.png} 같은 하위 폴더 산출물은
     * 걸리지 않는다 — 일지에 보여줄 이미지는 세션 폴더 최상위만이다.
     */
    private static final Pattern IMAGE_FILE_NAME = Pattern.compile(
            "^(event_\\d{2}\\.png|story_image\\.png)$"
    );
    private static final Pattern DIARY_OBJECT = Pattern.compile(
            "^(\\d{4}-\\d{2}-\\d{2})/session([1-6])/"
                    + "(event_\\d{2}\\.png|story_image\\.png|walk_log\\.md)$"
    );

    private static boolean isImageFile(String fileName) {
        return IMAGE_FILE_NAME.matcher(fileName).matches();
    }

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
        String markdownKey = objectPrefix + MARKDOWN_FILE;

        try {
            List<String> imageKeys = requireCompleteDiary(
                    ownedDevice,
                    objectPrefix
            );
            String markdown = readMarkdown(markdownKey);
            Instant expiresAt = Instant.now().plusSeconds(
                    properties.presignDurationSeconds()
            );
            List<String> imageUrls = imageKeys.stream()
                    .map(this::presignImage)
                    .toList();

            return new DiaryDetail(
                    deviceId,
                    walkDate,
                    session,
                    imageUrls.get(0),
                    imageUrls,
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
                // 일지와 이미지가 최소 한 장은 있어야 완성된 세션으로 본다.
                .filter(entry -> entry.getValue().contains(MARKDOWN_FILE)
                        && entry.getValue().stream()
                        .anyMatch(WalkDiaryService::isImageFile))
                .map(Map.Entry::getKey)
                .sorted(Comparator.comparing(DiaryReference::walkDate)
                        .reversed()
                        .thenComparingInt(DiaryReference::session))
                .toList();
    }

    /**
     * 세션의 이미지 키를 파일명 순서로 돌려준다.
     *
     * <p>일지나 이미지가 하나도 없으면 아직 완성되지 않은 세션이므로 404 로
     * 본다. S3 목록 순서를 믿지 않고 직접 정렬해서 {@code event_01 → event_04}
     * 순서를 보장한다 — 화면이 이 순서대로 보여준다.
     */
    private List<String> requireCompleteDiary(
            WalkDiaryStore.OwnedDevice device,
            String objectPrefix
    ) {
        List<String> imageKeys = new ArrayList<>();
        Set<String> files = new HashSet<>();
        listObjects(objectPrefix, object -> {
            if (!belongsToCurrentPairing(device, object)) {
                return;
            }
            String key = object.key();
            if (!key.startsWith(objectPrefix)) {
                return;
            }
            String fileName = key.substring(objectPrefix.length());
            if (fileName.equals(MARKDOWN_FILE)) {
                files.add(MARKDOWN_FILE);
            } else if (isImageFile(fileName)) {
                imageKeys.add(key);
            }
        });
        if (!files.contains(MARKDOWN_FILE) || imageKeys.isEmpty()) {
            throw new BusinessException(ErrorCode.WALK_DIARY_NOT_FOUND);
        }
        imageKeys.sort(Comparator.naturalOrder());
        return imageKeys;
    }

    private String presignImage(String imageKey) {
        return presigner.presignGetObject(
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
            /**
             * 첫 장({@code event_01.png}). 이미 배포된 앱이 이 필드만 읽으므로
             * 남겨둔다. 새 화면은 {@link #imageUrls} 를 쓴다.
             */
            String imageUrl,
            /** 세션의 이미지 전부. 파일명 순서(event_01 → event_04)다. */
            List<String> imageUrls,
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
