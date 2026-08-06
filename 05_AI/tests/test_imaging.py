"""imaging.encode_image 검증.

레거시와 바이트 비교가 불가능한 부분(cv2 -> PIL 교체)을
"규약을 지키는가"로 검증한다.
  - base64 예산을 절대 넘지 않는다
  - 긴 변이 MAX_SIDE 이하다
  - 예산 안의 파일은 원본 바이트를 그대로 보낸다(재인코딩하지 않는다)
"""

from __future__ import annotations

import base64
import io

import pytest
from PIL import Image, ImageFilter

from walklog import config
from walklog.gms import b64_length, encode_image


def _noise(size, seed):
    import random

    rnd = random.Random(seed)
    img = Image.new("RGB", size)
    img.putdata([(rnd.randrange(256), rnd.randrange(256), rnd.randrange(256))
                 for _ in range(size[0] * size[1])])
    return img


def make_jpeg(tmp_path, name="frame.jpg", size=(1296, 972), seed=7):
    """압축이 거의 먹지 않는 최악의 경우 픽스처.

    난수 픽셀은 JPEG 엔트로피 부호화가 손을 못 대서 실제 사진보다 훨씬 크다.
    예산 초과 경로와 2차 축소 경로를 강제로 태우는 데 쓴다.
    """
    path = tmp_path / name
    _noise(size, seed).save(path, format="JPEG", quality=95)
    return path


def make_photo_jpeg(tmp_path, name="photo.jpg", size=(1296, 972), seed=7):
    """실제 산책 프레임에 가까운 픽스처.

    난수에 가우시안 블러를 걸면 인접 픽셀 상관이 생겨 실제 사진과 비슷한
    압축률이 된다. 측정값: 원본 약 214KB(실제 프레임 191~236KB 범위),
    768px q80에서 base64 약 59,000자.
    """
    path = tmp_path / name
    _noise(size, seed).filter(ImageFilter.GaussianBlur(3)).save(
        path, format="JPEG", quality=95)
    return path


def test_b64_length_matches_real_encoding():
    for n in (0, 1, 2, 3, 4, 100, 999, 65_537):
        raw = b"x" * n
        assert b64_length(n) == len(base64.b64encode(raw))


def test_large_frame_fits_budget(tmp_path):
    """실제 프레임 크기(약 200KB)에서 예산을 지키는지."""
    path = make_jpeg(tmp_path)
    assert path.stat().st_size > config.MAX_INLINE_RAW_BYTES

    image = encode_image(path)
    assert len(image.b64) <= config.MAX_INLINE_B64_CHARS
    assert image.mime == "image/jpeg"

    decoded = Image.open(io.BytesIO(base64.b64decode(image.b64)))
    assert max(decoded.size) <= config.MAX_SIDE


def test_aspect_ratio_preserved(tmp_path):
    path = make_jpeg(tmp_path, size=(1296, 972))
    decoded = Image.open(io.BytesIO(base64.b64decode(encode_image(path).b64)))
    before = 1296 / 972
    after = decoded.size[0] / decoded.size[1]
    assert abs(before - after) < 0.02


def test_small_file_passes_through_unchanged(tmp_path):
    """예산 안의 파일은 재인코딩하지 않는다.

    PNG가 JPEG로 바뀌지 않아야 하고, 화질 손실도 없어야 한다.
    """
    img = Image.new("RGB", (64, 48), (120, 140, 160))
    path = tmp_path / "small.png"
    img.save(path, format="PNG")

    image = encode_image(path)
    assert image.mime == "image/png"
    assert base64.b64decode(image.b64) == path.read_bytes()


def test_unsupported_suffix(tmp_path):
    path = tmp_path / "frame.bmp"
    path.write_bytes(b"not an image")
    with pytest.raises(ValueError, match="지원하지 않는"):
        encode_image(path)


def test_corrupt_file(tmp_path):
    path = tmp_path / "broken.jpg"
    path.write_bytes(b"\xff\xd8\xff" + b"\x00" * 200_000)
    with pytest.raises(ValueError):
        encode_image(path)


def test_tight_budget_triggers_fallback(tmp_path, capsys):
    """예산을 좁히면 2차 축소가 발동하고 경고가 나오는지.

    난수 픽셀은 JPEG 압축이 거의 먹지 않아 최악의 경우다(측정값: 768px q50에서
    base64 137,072자, 512px q45에서 37,620자). 실제 사진은 이보다 훨씬 작아서
    기본 예산 88,000자에서는 2차 축소가 발동하지 않는다. 그래서 이 테스트는
    두 값 사이의 예산을 직접 지정해 경로를 강제한다.
    """
    budget = 50_000
    path = make_jpeg(tmp_path)
    image = encode_image(path, max_b64_chars=budget)

    assert len(image.b64) <= budget
    decoded = Image.open(io.BytesIO(base64.b64decode(image.b64)))
    assert max(decoded.size) <= config.FALLBACK_MAX_SIDE
    assert "낮췄습니다" in capsys.readouterr().err


def test_real_frame_avoids_fallback(tmp_path, capsys):
    """실제 프레임 크기/압축률에서는 2차 축소가 발동하지 않아야 한다.

    발동한다면 예산이 지나치게 좁다는 뜻이고, 그러면 해상도가 512px로 떨어져
    관찰 기록의 "불명"이 늘어난다. 첨부 전략 문서가 경고한 실패 모드다.
    """
    path = make_photo_jpeg(tmp_path)
    assert path.stat().st_size > config.MAX_INLINE_RAW_BYTES

    image = encode_image(path)
    assert len(image.b64) <= config.MAX_INLINE_B64_CHARS
    assert "낮췄습니다" not in capsys.readouterr().err

    decoded = Image.open(io.BytesIO(base64.b64decode(image.b64)))
    assert max(decoded.size) == config.MAX_SIDE


def test_impossible_budget_raises(tmp_path):
    path = make_jpeg(tmp_path)
    with pytest.raises(ValueError, match="재압축해도"):
        encode_image(path, max_b64_chars=200)