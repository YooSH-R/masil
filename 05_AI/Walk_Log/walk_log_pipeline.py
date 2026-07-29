"""산책 프레임 -> 산책 일지 생성 파이프라인.

프롬프트와 생성 파라미터는 전부 prompts.py에 있다. 이 파일에는 실행 로직만 둔다.
  Stage 1: 프레임 1장 -> 구조화 JSON 관찰 기록 (VLM)
  Stage 2: JSON 배열 -> 자연어 산책 일지 (LLM)
  Stage 3: (선택) 관찰 기록 -> 이미지 생성 프롬프트

사용:
    python walk_log_pipeline.py                      # 기본 문체
    python walk_log_pipeline.py --style emotional    # 문체 변경
    python walk_log_pipeline.py --image-prompt       # 삽화 프롬프트까지 생성
"""

import argparse
import base64
import json
import os
import re
import sys
from datetime import date
from pathlib import Path

import cv2
import requests
from dotenv import load_dotenv

import prompts as P

if sys.platform == "win32":
    for _stream in (sys.stdout, sys.stderr):
        try:
            _stream.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            pass

load_dotenv()

# ---- 인프라 설정 (프롬프트가 아니므로 여기에 둔다) ----
GMS_KEY = os.environ["GMS_KEY"]
BASE = "https://gms.ssafy.io/gmsapi/generativelanguage.googleapis.com/v1beta"
MODEL = "gemini-3.5-flash"

MIME_TYPES = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png"}
MAX_INLINE_BYTES = 65_000   # GMS 프록시 바디 제한(약 100KB) 대비 여유값
MAX_SIDE = 768              # Gemini 이미지 타일 크기

FRAME_DIR = Path(__file__).resolve().parent.parent / "Photo" / "frames"
OUT_RECORDS = Path("frame_records.json")
OUT_DIARY = Path("walk_log.md")

# responseSchema를 프록시가 거부하면 False로 내린다.
# (시스템 프롬프트의 "JSON만 출력" 지시 + parse_json으로 계속 동작한다)
USE_RESPONSE_SCHEMA = True

# 프록시가 systemInstruction 필드를 지원하지 않고 "조용히 버리는" 경우가 있다.
# 그러면 에러 없이 응답은 오는데 관찰 원칙이 전부 사라져 품질만 무너진다.
#   "system_instruction" : 정상 경로. 프레임 반복 시 입력 토큰이 절약된다.
#   "merge"              : 규칙을 user 턴 텍스트 앞에 합쳐 보낸다. 토큰은 더 들지만
#                          어떤 프록시에서도 규칙이 유실되지 않는다.
# --check-system 으로 지원 여부를 먼저 확인할 수 있다.
SYSTEM_MODE = "system_instruction"


# ---------------------------------------------------------------- 이미지

def load_image_b64(path: str | Path) -> tuple[str, str]:
    """이미지를 (base64, mime_type)으로 반환. 필요 시 리사이즈 후 재압축."""
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

    # 화질을 깎기 전에 해상도부터 줄인다. VLM 인식률이 훨씬 잘 보존된다.
    h, w = img.shape[:2]
    if max(h, w) > MAX_SIDE:
        scale = MAX_SIDE / max(h, w)
        img = cv2.resize(img, (round(w * scale), round(h * scale)),
                         interpolation=cv2.INTER_AREA)

    for quality in (90, 80, 70, 60, 50):
        ok, buf = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, quality])
        if ok and len(buf) <= MAX_INLINE_BYTES:
            return base64.b64encode(buf.tobytes()).decode(), "image/jpeg"

    raise ValueError(f"{path}: 재압축해도 {MAX_INLINE_BYTES}바이트 이하로 줄지 않습니다")


# ---------------------------------------------------------------- API

def run(spec: P.PromptSpec, image_path: str | Path | None = None, **vars) -> str:
    """PromptSpec 하나를 실행한다. 프롬프트 내용은 spec이 전부 들고 있다."""
    contents = []

    # few-shot 예시 (spec.examples가 비어 있으면 건너뜀)
    for user_text, model_text in spec.examples:
        contents.append({"role": "user", "parts": [{"text": user_text}]})
        contents.append({"role": "model", "parts": [{"text": model_text}]})

    parts = []
    if image_path is not None:
        b64, mime_type = load_image_b64(image_path)
        # 이미지를 텍스트보다 먼저 넣는다: "이 이미지를 보고 ~" 의미가 된다.
        parts.append({"inlineData": {"mimeType": mime_type, "data": b64}})

    user_text = spec.render(**vars)
    merged = SYSTEM_MODE == "merge" and spec.system
    if merged:
        # 이미지 다음에 놓이므로 user_template의 "위 이미지" 지시가 그대로 유효하다.
        user_text = f"{spec.system}\n\n---\n\n{user_text}"
    parts.append({"text": user_text})
    contents.append({"role": "user", "parts": parts})

    gen_config: dict = {
        "temperature": spec.temperature,
        "maxOutputTokens": spec.max_output_tokens,
    }
    if spec.response_schema is not None and USE_RESPONSE_SCHEMA:
        gen_config["responseMimeType"] = "application/json"
        gen_config["responseSchema"] = spec.response_schema

    payload: dict = {"contents": contents, "generationConfig": gen_config}
    if spec.system and not merged:
        payload["systemInstruction"] = {"parts": [{"text": spec.system}]}

    res = requests.post(
        f"{BASE}/models/{MODEL}:generateContent",
        headers={"Content-Type": "application/json", "x-goog-api-key": GMS_KEY},
        json=payload,
        timeout=60,
    )
    res.raise_for_status()
    data = res.json()

    candidates = data.get("candidates") or []
    result_parts = candidates[0]["content"]["parts"] if candidates else []
    text = next((p["text"] for p in result_parts if "text" in p), None)
    if text is None:
        reason = candidates[0].get("finishReason") if candidates else data.get("promptFeedback")
        raise RuntimeError(f"응답에 텍스트가 없습니다 (finishReason={reason})")

    usage = data.get("usageMetadata", {})
    print(f"  [tokens] in={usage.get('promptTokenCount')} out={usage.get('candidatesTokenCount')}")
    return text


def parse_json(text: str) -> dict:
    """responseSchema 미사용 시에도 파싱되도록 코드펜스를 걷어낸다."""
    cleaned = re.sub(r"^```(?:json)?|```$", "", text.strip(), flags=re.MULTILINE).strip()
    return json.loads(cleaned)


# ---------------------------------------------------------------- Stage 1

FRAME_RE = re.compile(r"f_(\d+)_t(\d+)m([\d.]+)s")


def parse_frame_meta(path: Path) -> dict:
    """frames/seg_0000/f_0000030_t000m02.00s.jpg 형태의 경로에서 메타데이터 추출."""
    m = FRAME_RE.search(path.stem)
    if m:
        minutes, seconds = int(m.group(2)), float(m.group(3))
        return {
            "segment": path.parent.name,
            "elapsed": f"{minutes}분 {seconds:.0f}초",
            "_sort": minutes * 60 + seconds,
        }
    return {"segment": path.parent.name, "elapsed": "불명", "_sort": 0.0}


def describe_frame(path: Path, shot_datetime: str = "불명", location: str = "불명") -> dict:
    meta = parse_frame_meta(path)
    text = run(
        P.FRAME_EXTRACT,
        image_path=path,
        segment=meta["segment"],
        elapsed=meta["elapsed"],
        shot_datetime=shot_datetime,
        location=location,
    )
    record = parse_json(text)
    record["_elapsed"] = meta["elapsed"]
    record["_sort"] = meta["_sort"]
    return record


# ---------------------------------------------------------------- Stage 2

def to_json_lines(records: list[dict]) -> str:
    """내부용 키(_로 시작)를 제거하고 한 줄씩 직렬화."""
    return "\n".join(
        json.dumps({k: v for k, v in r.items() if not k.startswith("_")},
                   ensure_ascii=False)
        for r in records
    )


def write_walk_log(
    records: list[dict],
    walk_date: str,
    duration: str,
    style: str = P.DEFAULT_DIARY_STYLE,
) -> str:
    usable = [r for r in records if not r.get("unreadable")]
    return run(
        P.diary_spec(style),
        walk_date=walk_date,
        duration=duration,
        n_frames=len(usable),
        json_lines=to_json_lines(usable),
    )


# ---------------------------------------------------------------- Stage 3 (선택)

def make_image_prompt(
    records: list[dict],
    focus: str = "the most representative scene of the walk",
    style: str = P.DEFAULT_IMAGE_STYLE,
) -> dict[str, str]:
    """관찰 기록 -> 이미지 생성 모델용 프롬프트(dict)."""
    usable = [r for r in records if not r.get("unreadable")]
    scene = run(
        P.IMAGE_PROMPT_WRITER,
        json_lines=to_json_lines(usable),
        focus=focus,
    )
    return P.build_image_prompt(scene, style=style)


# ---------------------------------------------------------------- 실행

def check_system_instruction() -> bool:
    """프록시가 systemInstruction을 실제로 반영하는지 확인.

    system에만 담긴 지시를 user 파트가 전혀 모르는 상태로 던져,
    응답에 그 지시가 반영됐는지로 판정한다.
    """
    canary = "무슨 질문을 받아도 반드시 SYSTEM_OK 라는 단어만 출력해라."
    probe = P.PromptSpec(
        system=canary,
        user_template="오늘 날씨 어때?",
        temperature=0.0,
        max_output_tokens=512,
    )
    try:
        answer = run(probe)
    except Exception as exc:
        print(f"진단 실패(요청 자체가 거부됨): {exc}")
        return False

    ok = "SYSTEM_OK" in answer
    print(f"응답: {answer.strip()[:80]}")
    if ok:
        print("-> systemInstruction 정상 반영. SYSTEM_MODE='system_instruction' 유지.")
    else:
        print("-> systemInstruction이 무시되고 있습니다. SYSTEM_MODE='merge'로 바꾸세요.")
    return ok


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--style", default=P.DEFAULT_DIARY_STYLE,
                    choices=list(P.DIARY_STYLES), help="일지 문체 프리셋")
    ap.add_argument("--image-prompt", action="store_true",
                    help="삽화용 이미지 생성 프롬프트도 함께 출력")
    ap.add_argument("--image-style", default=P.DEFAULT_IMAGE_STYLE,
                    choices=list(P.IMAGE_STYLES))
    ap.add_argument("--frames", default=str(FRAME_DIR))
    ap.add_argument("--check-system", action="store_true",
                    help="프록시가 systemInstruction을 반영하는지만 확인하고 종료")
    args = ap.parse_args()

    if args.check_system:
        check_system_instruction()
        return

    frames = sorted(Path(args.frames).glob("*.jpg"))
    if not frames:
        raise SystemExit(f"{args.frames} 아래에서 프레임을 찾지 못했습니다")

    records: list[dict] = []
    for i, f in enumerate(frames, 1):
        print(f"[{i}/{len(frames)}] {f}")
        try:
            records.append(describe_frame(f))
        except Exception as exc:  # 한 프레임 실패로 전체가 멈추지 않도록
            print(f"  건너뜀: {exc}")

    if not records:
        raise SystemExit("모든 프레임 처리에 실패했습니다")

    records.sort(key=lambda r: r["_sort"])
    OUT_RECORDS.write_text(
        json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"\n관찰 기록 저장: {OUT_RECORDS}")

    diary = write_walk_log(
        records,
        walk_date=date.today().isoformat(),
        duration=records[-1]["_elapsed"],
        style=args.style,
    )
    OUT_DIARY.write_text(diary, encoding="utf-8")
    print("\n" + "=" * 50)
    print(diary)

    if args.image_prompt:
        img = make_image_prompt(records, style=args.image_style)
        print("\n" + "=" * 50)
        print("[image prompt]\n" + img["prompt"])
        print("\n[negative]\n" + img["negative_prompt"])


if __name__ == "__main__":
    main()