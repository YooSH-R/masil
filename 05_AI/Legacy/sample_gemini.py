import base64
import os
import sys
from pathlib import Path

import cv2
import requests
from dotenv import load_dotenv

if sys.platform == "win32":
    for _stream in (sys.stdout, sys.stderr):
        try:
            _stream.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            pass

load_dotenv()

GMS_KEY = os.environ["GMS_KEY"]  # 키는 절대 코드에 하드코딩하지 마세요
BASE = "https://gms.ssafy.io/gmsapi/generativelanguage.googleapis.com/v1beta"
MODEL = "gemini-3.5-flash"

MIME_TYPES = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
}

# 이 GMS 프록시는 요청 바디가 대략 100KB를 넘으면
# "contents is not specified" 400 에러를 반환합니다 (실측 확인).
# 여유를 두고 원본 이미지 바이트 기준 65KB를 목표로 재압축합니다.
MAX_INLINE_BYTES = 65_000


def load_image_b64(path: str | Path) -> tuple[str, str]:
    """이미지를 읽어 (base64 문자열, mime_type)을 반환.

    원본이 크기 제한을 넘으면 JPEG로 재인코딩하며 화질을 낮춰갑니다.
    """
    path = Path(path)
    raw = path.read_bytes()
    mime_type = MIME_TYPES.get(path.suffix.lower())
    if mime_type is None:
        raise ValueError(f"지원하지 않는 이미지 확장자: {path.suffix}")

    if len(raw) <= MAX_INLINE_BYTES:
        return base64.b64encode(raw).decode(), mime_type

    img = cv2.imread(str(path))
    if img is None:
        raise ValueError(f"이미지를 읽을 수 없습니다: {path}")

    for quality in (80, 65, 50, 35, 20):
        ok, buf = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, quality])
        if ok and len(buf) <= MAX_INLINE_BYTES:
            return base64.b64encode(buf.tobytes()).decode(), "image/jpeg"

    raise ValueError(f"{path}: 재압축해도 {MAX_INLINE_BYTES}바이트 이하로 줄지 않습니다")


def ask(
    prompt: str,
    system: str | None = None,
    image_path: str | Path | None = None,
) -> str:
    parts = []
    if image_path is not None:
        b64, mime_type = load_image_b64(image_path)
        parts.append({"inlineData": {"mimeType": mime_type, "data": b64}})
    parts.append({"text": prompt})

    payload = {
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": {
            "temperature": 0.7,
            "maxOutputTokens": 2048,
        },
    }
    if system:
        payload["systemInstruction"] = {"parts": [{"text": system}]}

    res = requests.post(
        f"{BASE}/models/{MODEL}:generateContent",
        headers={
            "Content-Type": "application/json",
            "x-goog-api-key": GMS_KEY,
        },
        json=payload,
        timeout=60,
    )
    res.raise_for_status()
    data = res.json()

    # gemini-3.5-flash는 추론(thinking) 모델이라 maxOutputTokens을
    # thinking에 다 써버리면 답변 text 파트가 없을 수 있습니다.
    candidates = data.get("candidates") or []
    result_parts = candidates[0]["content"]["parts"] if candidates else []
    text = next((p["text"] for p in result_parts if "text" in p), None)
    if text is None:
        reason = candidates[0].get("finishReason") if candidates else data.get("promptFeedback")
        raise RuntimeError(f"응답에 텍스트가 없습니다 (finishReason={reason})")

    usage = data.get("usageMetadata", {})
    print(f"[tokens] in={usage.get('promptTokenCount')} out={usage.get('candidatesTokenCount')}")
    return text


if __name__ == "__main__":
    print(ask(
        "이 이미지에 무엇이 보이는지 한국어로 설명해줘.",
        image_path="frames/seg_0000/f_0000030_t000m02.00s.jpg",
    ))
