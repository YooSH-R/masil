"""GMS 프록시 호출 계층.

  imaging.py  사진 -> (base64, mime). PIL 의존은 이 파일만.
  payload.py  PromptSpec -> 요청 dict. 순수 함수. 네트워크/파일/이미지 의존 없음.
  client.py   요청 dict -> HTTP -> GenResult.

의존 방향은 client -> (payload, imaging) -> config 한 방향이다.
payload는 imaging을 import하지 않는다. 그래야 요청 조립을
사진 없이, PIL 없이 검증할 수 있다.
"""

from __future__ import annotations

from .client import (
    GenResult,
    GMSAuthError,
    GMSClient,
    GMSEmptyResponse,
    GMSError,
    GMSHTTPError,
    GMSNetworkError,
    strip_code_fence,
)
from .imaging import b64_length, encode_image
from .payload import (
    IMAGE_GENERATION_CONFIG,
    InlineImage,
    build_payload,
    fingerprint_payload,
    payload_from_spec,
    spec_generation_config,
)


__all__ = [
    "GMSClient",
    "GenResult",
    "GMSError",
    "GMSAuthError",
    "GMSHTTPError",
    "GMSNetworkError",
    "GMSEmptyResponse",
    "strip_code_fence",
    "encode_image",
    "b64_length",
    "InlineImage",
    "build_payload",
    "payload_from_spec",
    "spec_generation_config",
    "fingerprint_payload",
    "IMAGE_GENERATION_CONFIG",
]