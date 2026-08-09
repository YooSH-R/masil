"""프로젝트 공용 설정.

[이 파일의 역할]
프롬프트가 아닌 모든 상수를 여기 모은다. API 주소, 모델명, 크기 제한, 경로,
기본 동작 플래그. 값을 바꾸려면 이 파일만 보면 된다.

[이 파일이 하지 않는 것]
requests, PIL을 import하지 않는다. 프롬프트 문자열을 갖지 않는다.
import 시점에 예외를 던지지 않는다 - 키가 없어도 import는 성공해야 한다.
(테스트와 프롬프트 편집이 .env 없이도 가능해야 하기 때문이다)

[분할 전에서 바뀐 점]
1. GMS_KEY를 모듈 상수에서 get_key() 함수로 바꿨다. 전에는 import만 해도 KeyError였다.
2. 프레임 기본 경로를 존재하지 않는 ../Photo/frames 에서 data/sample_image 로 고쳤다.
3. 출력 경로 기준을 통일했다. 전에는 프레임 경로는 파일 기준, 출력 경로는 cwd 기준이라
   어디서 실행하느냐에 따라 결과 위치가 달라졌다.
4. MODEL 하나를 TEXT_MODEL / IMAGE_MODEL 로 나눴다.
5. 인라인 이미지 크기 상한의 단위를 이름에 명시했다. 아래 주석 참고.
"""

from __future__ import annotations

import os
from datetime import date
from pathlib import Path

__all__ = [
    "ConfigError",
    "PROJECT_ROOT",
    "DATA_DIR",
    "DEFAULT_FRAME_DIR",
    "OUTPUTS_DIR",
    "RECORDS_NAME",
    "DIARY_NAME",
    "FLOW_IMAGE_NAME",
    "STORY_IMAGE_NAME",
    "JOURNAL_NAME",
    "IMAGE_MANIFEST_NAME",
    "S3_UPLOAD_EXCLUDE_DIRS",
    "PANELS_DIRNAME",
    "PAYLOAD_DIRNAME",
    "SESSION_PREFIX",
    "date_dir",
    "list_sessions",
    "run_dir",
    "KEY_ENV",
    "get_key",
    "BASE",
    "TEXT_MODEL",
    "IMAGE_MODEL",
    "REQUEST_TIMEOUT",
    "IMAGE_TIMEOUT",
    "MIME_TYPES",
    "IMAGE_SUFFIXES",
    "MAX_BODY_CHARS",
    "MAX_INLINE_B64_CHARS",
    "MAX_INLINE_RAW_BYTES",
    "MAX_SIDE",
    "FALLBACK_MAX_SIDE",
    "FALLBACK_QUALITY",
    "JPEG_QUALITY_LADDER",
    "S3_BUCKET",
    "DEVICE_ID",
    "S3_PREFIX",
    "AWS_REGION",
    "FONT_ENV",
    "FONT_CANDIDATES",
    "SYSTEM_MODES",
    "SYSTEM_MODE",
    "USE_RESPONSE_SCHEMA",
    "check_system_mode",
    "SAMPLE_RATIO",
    "SAMPLE_MIN",
    "SAMPLE_MAX",
]


class ConfigError(RuntimeError):
    """설정이 없거나 잘못됐을 때. 호출부가 사용자에게 그대로 보여줄 수 있는 메시지를 담는다."""


# ============================================================ 경로

# 이 파일은 <프로젝트 루트>/walklog/config.py 에 있다.
# 실행 위치(cwd)가 아니라 파일 위치를 기준으로 잡으므로,
# 어느 디렉터리에서 실행해도 같은 곳을 가리킨다.
PROJECT_ROOT = Path(__file__).resolve().parent.parent       # <== .\PJT\05_AI

DATA_DIR = PROJECT_ROOT / "data"                    # <-- 데이터 폴더 경로
DEFAULT_FRAME_DIR = DATA_DIR / "sample_image"       # <-- 이미지 경로
OUTPUTS_DIR = PROJECT_ROOT / "outputs"              # <-- 산출물 경로


# 실행 결과 파일 이름. 실행마다 날짜 폴더 아래에 생긴다.
RECORDS_NAME = "frame_records.json"
DIARY_NAME = "walk_log.md"
FLOW_IMAGE_NAME = "walk_flow.png"
STORY_IMAGE_NAME = "story_image.png"
JOURNAL_NAME = "walk_journal.png"
PANELS_DIRNAME = "flow_panels"

# 이미지가 생성될 때마다 최종 프롬프트/스타일/참조/검사 이력을 append하는
# 진단용 기록. 화풍 드리프트가 재발했을 때 "이 이미지가 정확히 어떤 요청으로
# 만들어졌는가"를 되짚을 수 있게 한다 (illustrate._log_image_generation).
IMAGE_MANIFEST_NAME = "image_manifest.json"

PAYLOAD_DIRNAME = "payload"

# 세션 폴더는 통째로 S3에 미러링한다(storage.upload_outputs). 단 payload/
# (디버그용 요청 덤프)는 base64 인라인 이미지가 포함되어 크고, 진단 목적의
# 로컬 기록이므로 제외한다. 예전에는 허용 목록(S3_UPLOAD_FILES) 방식이었는데,
# 새 산출물(예: flow_panels/, image_manifest.json)이 생길 때마다 목록에
# 추가하지 않으면 조용히 안 올라가는 문제가 있었다.
S3_UPLOAD_EXCLUDE_DIRS = (PAYLOAD_DIRNAME,)


SESSION_PREFIX = "session"


def date_dir(day: date | str | None = None) -> Path:
    """그 날짜의 outputs 폴더. 세션 폴더들의 부모. 예: outputs/2026-07-29

    조회 전용이다 - 폴더를 만들지 않는다. list_sessions가 존재 여부만
    확인할 때 부작용 없이 쓸 수 있어야 하기 때문이다.
    """
    if day is None:
        day = date.today()
    stamp = day.isoformat() if isinstance(day, date) else str(day)
    return OUTPUTS_DIR / stamp


def list_sessions(day: date | str | None = None) -> list[int]:
    """그 날짜에 이미 있는 세션 번호를 오름차순으로 반환한다.

    하루에 산책을 여러 번 다녀오면 run_walk_log.py도 여러 번 돌게 되는데,
    예전에는 outputs/<날짜>/ 에 바로 결과를 써서 두 번째 실행이 첫 번째
    산책 기록을 덮어썼다. session1, session2, ... 폴더로 나누면 실행마다
    새 폴더가 생겨 이전 산책 기록이 사라지지 않는다.
    """
    base = date_dir(day)
    if not base.is_dir():
        return []
    numbers = []
    for path in base.iterdir():
        if path.is_dir() and path.name.startswith(SESSION_PREFIX):
            suffix = path.name[len(SESSION_PREFIX):]
            if suffix.isdigit():
                numbers.append(int(suffix))
    return sorted(numbers)


def run_dir(day: date | str | None = None, *, session: int | None = None,
           create: bool = True) -> Path:
    """실행 결과를 담을 폴더를 반환한다. 예: outputs/2026-07-29/session1

    session을 주면 그 번호의 세션 폴더를, 안 주면 날짜 폴더 바로 아래를
    가리킨다(세션을 나누기 전의 동작과 호환). "다음 세션을 새로 만들지,
    최근 세션을 이어 쓸지"를 정하는 로직은 CLI 맥락(새 산책 기록인지,
    이미 있는 기록으로 삽화만 만드는지)에 따라 다르므로 여기 두지 않는다
    - cli/common.py의 resolve_run_dir 참고.
    """
    base = date_dir(day)
    path = base / f"{SESSION_PREFIX}{session}" if session is not None else base
    if create:
        path.mkdir(parents=True, exist_ok=True)
    return path


# ============================================================ 인증

KEY_ENV = "GMS_KEY"

_env_loaded = False


def _load_env_once() -> None:
    """.env를 os.environ으로 한 번만 읽어들인다.

    python-dotenv가 없거나 .env가 없어도 조용히 넘어간다.
    환경변수를 직접 주입하는 실행 환경을 막지 않기 위해서다.
    """
    global _env_loaded
    if _env_loaded:
        return
    _env_loaded = True
    try:
        from dotenv import load_dotenv
    except ImportError:
        return
    load_dotenv(PROJECT_ROOT / ".env")


def get_key(env: str = KEY_ENV) -> str:
    """GMS API 키를 반환한다. 없으면 무엇을 해야 하는지 알려주는 예외를 던진다.

    모듈 상수가 아니라 함수인 이유:
    import만으로 키를 요구하면 키 없는 환경에서 프롬프트 테스트조차 못 돌린다.
    실제로 API를 부르는 순간에만 필요하다.
    """
    _load_env_once()
    key = os.environ.get(env, "").strip()
    if not key:
        raise ConfigError(
            f"환경변수 {env}가 비어 있습니다. "
            f"{PROJECT_ROOT / '.env'} 에 {env}=<발급받은 키> 를 넣어 주세요. "
            f"(.env.sample 참고)"
        )
    return key


# ============================================================ API

# .env가 먼저 로드되어야 아래 os.environ.get이 .env 값을 볼 수 있다.
_load_env_once()

BASE = os.environ.get(
    "GMS_BASE",
    "https://gms.ssafy.io/gmsapi/generativelanguage.googleapis.com/v1beta",
).rstrip("/")

# 텍스트/비전 모델과 이미지 생성 모델은 다르다.
# 전에는 MODEL 하나가 상수로 박혀 있어서 삽화 생성 쪽이 이 값을 쓸 수 없었다.
TEXT_MODEL = os.environ.get("GMS_TEXT_MODEL", "gemini-3.5-flash")
IMAGE_MODEL = os.environ.get("GMS_IMAGE_MODEL", "gemini-2.5-flash-image")

REQUEST_TIMEOUT = int(os.environ.get("GMS_TIMEOUT", "60"))
# 이미지 생성은 텍스트보다 훨씬 느리다. 60초로는 자주 끊긴다.
IMAGE_TIMEOUT = int(os.environ.get("GMS_IMAGE_TIMEOUT", "180"))


# ============================================================ 인라인 이미지

MIME_TYPES = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png"}
IMAGE_SUFFIXES = tuple(MIME_TYPES)

# GMS 프록시가 받아주는 요청 바디 대략 상한. 아래 예산의 근거값이다.
MAX_BODY_CHARS = 100_000

# 인라인 이미지 상한. 단위는 "base64로 인코딩한 후의 문자열 길이"다.
#
# 분할 전에는 이 상수가 MAX_INLINE_BYTES 하나였는데,
# 파이프라인은 raw 바이트로, 삽화 스크립트는 base64 길이로 서로 다르게 해석했다.
# 단위가 이름에 없어서 생긴 사고이므로 이름에 단위를 박는다.
#
# 88,000자를 쓰는 근거:
#   base64(88,000) + 시스템/유저 프롬프트 + responseSchema ≈ 91,000자 < 100,000자
# 이는 분할 전 파이프라인의 실질 예산과 같다(raw 65,000 -> base64 86,667).
# 여기를 더 조이면 재압축 화질이 떨어져 관찰 기록의 "불명"이 늘어난다.
MAX_INLINE_B64_CHARS = 88_000

# base64는 원본의 약 4/3이 되므로 원본 JPEG 예산은 이 값이다.
MAX_INLINE_RAW_BYTES = MAX_INLINE_B64_CHARS * 3 // 4   # 66,000

# Gemini 이미지 타일 크기. 긴 변을 이 값에 맞춘다.
# 튜닝 참고: 관찰 기록에 "불명"이 많으면 프롬프트가 아니라 이 값을 먼저 본다.
# 해상도가 부족하면 어떤 프롬프트를 써도 판별이 안 된다.
MAX_SIDE = 768

# 화질을 다 낮춰도 예산을 못 맞출 때의 2차 축소.
FALLBACK_MAX_SIDE = 512
FALLBACK_QUALITY = 45

# 재압축 품질 후보. 앞에서부터 시도해 예산에 처음 들어가는 값을 쓴다.
# 높은 품질을 먼저 시도한다. VLM 인식률이 압축 잡음에 민감하기 때문이다.
JPEG_QUALITY_LADDER = (90, 80, 70, 60, 50)


# ============================================================ S3 업로드

# 버킷 이름은 비밀이 아니므로 GMS_KEY와 달리 지연 평가(get_key 스타일) 없이
# 모듈 상수로 둔다. 자격증명(액세스 키)은 여기서 다루지 않는다 - boto3의
# 기본 자격증명 체인(환경변수 -> ~/.aws/credentials -> IAM 역할)에 맡긴다.
S3_BUCKET = os.environ.get("S3_BUCKET", "walk-picture-s3-483461801092-ap-northeast-2-an")

# 이 서버/컨테이너가 대신 업로드해 주는 로봇의 식별자. 로봇이 여러 대가 되면
# 기기별로 버킷 경로가 겹치지 않아야 하므로, S3_PREFIX 자체가 아니라 이 값을
# 따로 두고 조합한다 - 나중에 기기가 늘어도 DEVICE_ID 하나만 바꾸면 된다.
DEVICE_ID = os.environ.get("DEVICE_ID", "device-001")

# outputs/<날짜>/session<N>/ 를 그대로 이 프리픽스 아래에 미러링한다.
# 최종 경로: robot-images/<DEVICE_ID>/<날짜>/session<N>/<파일>
S3_PREFIX = os.environ.get("S3_PREFIX", f"robot-images/{DEVICE_ID}").strip("/")
AWS_REGION = os.environ.get("AWS_REGION", "ap-northeast-2")


# ============================================================ 폰트 (스토리보드 캡션)

# OS마다 경로가 다른 환경 의존 값이므로 config가 소유한다.
# 여백/글자 크기 같은 레이아웃 값은 stages/illustrate.py 에 둔다(그 파일에서만 쓴다).
FONT_ENV = "WALKLOG_FONT"
FONT_CANDIDATES = tuple(p for p in (
    os.environ.get(FONT_ENV, ""),
    "C:/Windows/Fonts/malgun.ttf",
    "/usr/share/fonts/truetype/nanum/NanumGothic.ttf",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
    "/System/Library/Fonts/AppleSDGothicNeo.ttc",
    # 한글 글리프가 없다. 최후 수단이며 캡션이 깨진다.
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
) if p)


# ============================================================ 요청 조립 기본값

# 프록시가 systemInstruction 필드를 지원하지 않고 "조용히 버리는" 경우가 있다.
# 그러면 에러 없이 응답은 오는데 관찰 원칙이 전부 사라져 품질만 무너진다.
#   "system_instruction" : 정상 경로. 프레임 반복 시 입력 토큰이 절약된다.
#   "merge"              : 규칙을 user 턴 텍스트 앞에 합쳐 보낸다. 토큰은 더 들지만
#                          어떤 프록시에서도 규칙이 유실되지 않는다.
# 지원 여부는 walklog.diagnostics 로 확인한다.
SYSTEM_MODES = ("system_instruction", "merge")
SYSTEM_MODE = os.environ.get("GMS_SYSTEM_MODE", "system_instruction")

# responseSchema를 프록시가 거부하면 0으로 내린다.
# (시스템 프롬프트의 "JSON만 출력" 지시 + 코드펜스 제거로 계속 동작한다)
USE_RESPONSE_SCHEMA = os.environ.get("GMS_USE_RESPONSE_SCHEMA", "1") not in ("0", "false", "False")


# ============================================================ 표본 크기

# Stage 1 표본 크기. 추출된 프레임의 SAMPLE_RATIO 만큼 관찰하되,
# 흐름 파악 최소치(SAMPLE_MIN)와 VLM 비용 상한(SAMPLE_MAX) 사이로 묶는다.
SAMPLE_RATIO = 0.10
SAMPLE_MIN = 4
SAMPLE_MAX = 12


def check_system_mode(mode: str) -> str:
    """system_mode 값을 검증해 그대로 반환한다.

    오타가 나면 조용히 "merge가 아니다"로 처리되어 systemInstruction 경로를 타므로,
    잘못된 값은 여기서 즉시 걸러야 한다.
    """
    if mode not in SYSTEM_MODES:
        raise ConfigError(f"알 수 없는 system_mode: {mode!r} (사용 가능: {list(SYSTEM_MODES)})")
    return mode