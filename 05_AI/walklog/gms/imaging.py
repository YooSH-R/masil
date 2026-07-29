"""이미지를 GMS 인라인 전송 예산 안에 넣는다.

[분할 전 상태]
같은 일을 하는 코드가 두 벌 있었다.
  walk_log_pipeline.load_image_b64  : cv2, raw 바이트를 65,000과 비교
  generate_flow_image.encode_ref    : PIL, base64 길이를 65,000과 비교
같은 상수를 서로 다른 단위로 해석했고, 파이프라인 쪽은 base64 팽창(4/3)을
계산에 넣지 않아 실제 전송량이 예산의 1.33배였다.

[통일 방침]
PIL로 합친다. 근거는 셋이다.
  1. base64 길이를 기준으로 판정하는 encode_ref 쪽 계산이 옳다.
  2. Pillow는 스토리보드 합성에 이미 필수 의존이다. cv2를 뺄 수 있다.
  3. 인코딩 경로가 하나면 두 스테이지의 이미지 화질이 항상 같다.

[의도한 동작 변경]
cv2와 PIL은 같은 품질값에서도 다른 JPEG를 만든다. 따라서 재압축이 일어나는
프레임의 바이트는 분할 전과 다르다. 예산과 해상도 상한은 동일하게 유지했으므로
화질 수준은 같다. optimize=True는 같은 품질에서 파일이 더 작아지는 무료 이득이라 켰다.
"""

from __future__ import annotations

import base64
import io
from pathlib import Path

from PIL import Image

from .. import config
from ..console import warn
from .payload import InlineImage

__all__ = ["b64_length", "encode_image"]


def b64_length(raw_len: int) -> int:
    """raw 바이트 수에 대응하는 base64 문자열 길이. 패딩까지 계산한다."""
    return 4 * ((raw_len + 2) // 3)


def _encode(raw: bytes) -> str:
    return base64.b64encode(raw).decode("ascii")


def _jpeg_bytes(img: Image.Image, quality: int) -> bytes:
    buf = io.BytesIO()
    # optimize=True: 같은 품질에서 파일이 작아진다. 예산 여유가 화질로 돌아온다.
    img.save(buf, format="JPEG", quality=quality, optimize=True)
    return buf.getvalue()


def encode_image(
    path: str | Path,
    *,
    max_b64_chars: int = config.MAX_INLINE_B64_CHARS,
    max_side: int = config.MAX_SIDE,
    quality_ladder: tuple[int, ...] = config.JPEG_QUALITY_LADDER,
    fallback_side: int = config.FALLBACK_MAX_SIDE,
    fallback_quality: int = config.FALLBACK_QUALITY,
) -> InlineImage:
    """이미지를 (base64, mime)으로 반환한다. 예산을 넘으면 축소 후 재압축한다.

    순서가 중요하다. 화질을 깎기 전에 해상도부터 줄인다.
    VLM 인식률은 압축 잡음보다 해상도에 덜 민감하지만, 잡음이 심해지면
    "불명" 판정이 늘어난다. 그래서 긴 변을 먼저 max_side에 맞춘 뒤
    품질을 높은 쪽부터 시도한다.
    """
    path = Path(path)
    mime = config.MIME_TYPES.get(path.suffix.lower())
    if mime is None:
        raise ValueError(
            f"지원하지 않는 이미지 확장자: {path.suffix} "
            f"(가능: {', '.join(config.IMAGE_SUFFIXES)})"
        )

    raw = path.read_bytes()

    # 예산 안에 들어오면 원본 바이트를 그대로 보낸다.
    # 재인코딩하지 않으므로 PNG는 PNG로 남고 화질 손실도 없다.
    if b64_length(len(raw)) <= max_b64_chars:
        return InlineImage(_encode(raw), mime)

    try:
        img = Image.open(io.BytesIO(raw))
        img.load()
    except OSError as exc:
        raise ValueError(f"이미지를 읽을 수 없습니다: {path} ({exc})") from exc

    if img.mode not in ("RGB", "L"):
        img = img.convert("RGB")

    # thumbnail은 축소만 한다(확대하지 않는다). 비율도 유지한다.
    img.thumbnail((max_side, max_side), Image.LANCZOS)

    for quality in quality_ladder:
        data = _jpeg_bytes(img, quality)
        if b64_length(len(data)) <= max_b64_chars:
            return InlineImage(_encode(data), "image/jpeg")

    # 품질을 다 낮춰도 안 되면 해상도를 한 단계 더 줄인다.
    img.thumbnail((fallback_side, fallback_side), Image.LANCZOS)
    data = _jpeg_bytes(img, fallback_quality)
    if b64_length(len(data)) <= max_b64_chars:
        warn(
            f"{path.name}: 예산을 맞추기 위해 {fallback_side}px / 품질 {fallback_quality}"
            f"까지 낮췄습니다. 관찰 기록의 '불명'이 늘어날 수 있습니다."
        )
        return InlineImage(_encode(data), "image/jpeg")

    raise ValueError(
        f"{path.name}: 재압축해도 base64 {max_b64_chars:,}자 이하로 줄지 않습니다 "
        f"(현재 {b64_length(len(data)):,}자)"
    )