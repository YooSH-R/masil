"""산책 전체 흐름 삽화 생성.

frames/ + frame_records.json  ->  시간순 스토리보드 이미지 1장

  Stage A  관찰 기록 -> 장면 전환 감지 -> 대표 프레임 N장 선정   (로컬, API 없음)
  Stage B  각 장면 -> 영어 이미지 프롬프트                      (LLM)
  Stage C  각 장면 -> 삽화 생성                                 (이미지 모델)
  Stage D  삽화들 -> 스토리보드 합성                            (로컬, Pillow)

프롬프트는 전부 prompts.py 에서 가져온다. 이 파일에는 실행 로직만 둔다.
prompts.py 에 IMAGE_PROMPT_WRITER / FLOW_IMAGE_WRITER / PANEL_CAPTION_WRITER /
IMAGE_STYLES / IMAGE_NEGATIVE / build_image_prompt 가 없으면 즉시 에러를 낸다
(내장 대체 프롬프트는 두지 않는다 - 관리 지점이 두 곳으로 쪼개지는 걸 막기 위해서다).

사용:
    python generate_flow_image.py
    python generate_flow_image.py -n 5 --style watercolor
    python generate_flow_image.py --mode single          # 한 장으로 요약
    python generate_flow_image.py --no-ref               # 실제 프레임 참조 없이 생성
    python generate_flow_image.py --layout grid --dry-run
"""

from __future__ import annotations

import argparse
import base64
import io
import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import requests
from dotenv import load_dotenv
from PIL import Image, ImageDraw, ImageFont

import prompts as P

if sys.platform == "win32":
    for _stream in (sys.stdout, sys.stderr):
        try:
            _stream.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            pass

load_dotenv()

# ---- 인프라 설정 (프롬프트가 아니므로 여기에 둔다) --------------------------
BASE = "https://gms.ssafy.io/gmsapi/generativelanguage.googleapis.com/v1beta"
TEXT_MODEL = "gemini-3.5-flash"
IMAGE_MODEL = "gemini-2.5-flash-image"

# GMS 프록시 바디 제한(약 100KB) 대비 여유값. walk_log_pipeline.py 와 동일 기준.
MAX_INLINE_BYTES = 65_000
REF_MAX_SIDE = 768            # 참조 프레임 리사이즈 상한

# frames/ 는 이 파일 위치(AI/) 기준이 아니라 Photo/frames 에 있다.
# cwd 상대경로로 두면 실행 위치에 따라 조용히 못 찾는다 (walk_log_pipeline.py와 동일 이슈).
DEFAULT_FRAME_DIR = Path(__file__).resolve().parent.parent / "Photo" / "frames"
DEFAULT_RECORDS = Path("frame_records.json")
DEFAULT_OUT = Path("walk_flow.png")
PANEL_DIR = Path("flow_panels")   # 개별 삽화 보관 (재실행 시 캐시로도 쓴다)

# 스토리보드 레이아웃
PANEL_W = 512
CAPTION_H = 56
TITLE_H = 72
GAP = 14
MARGIN = 24
BG = (250, 249, 246)
FG = (38, 38, 38)
SUB = (120, 120, 120)

# 한국어 캡션용 폰트 후보. --font 로 직접 지정할 수도 있다.
FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/nanum/NanumGothic.ttf",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "C:/Windows/Fonts/malgun.ttf",
    "/System/Library/Fonts/AppleSDGothicNeo.ttc",
]


# ============================================================ prompts.py 연동

def load_prompts() -> tuple[Any, Any, Any, dict[str, str], str, Any]:
    """이미지 생성에 필요한 프롬프트 스펙을 전부 prompts.py에서 가져온다.

    이 파일에는 실행 로직만 두고 프롬프트 내용은 prompts.py가 유일한 소스여야 하므로
    내장 대체 프롬프트를 두지 않는다. 없으면 조용히 다른 문구로 돌아가는 대신
    바로 에러를 내서 prompts.py 수정 누락을 곧바로 알아챌 수 있게 한다.
    """
    required = ("IMAGE_PROMPT_WRITER", "FLOW_IMAGE_WRITER", "PANEL_CAPTION_WRITER",
                "IMAGE_STYLES", "IMAGE_NEGATIVE", "build_image_prompt")
    missing = [name for name in required if getattr(P, name, None) is None]
    if missing:
        sys.exit(f"[에러] prompts.py에 다음 항목이 없습니다: {', '.join(missing)}")

    return (P.IMAGE_PROMPT_WRITER, P.FLOW_IMAGE_WRITER, P.PANEL_CAPTION_WRITER,
            P.IMAGE_STYLES, P.IMAGE_NEGATIVE, P.build_image_prompt)


# ============================================================ 기록 정규화

@dataclass
class Scene:
    index: int
    image: Path | None
    elapsed: str
    record: dict[str, Any]
    meta: dict[str, Any] | None = None   # 기록의 최상위 dict (segment, shot_datetime 등)
    weight: int = 1                      # 이 장면에 속한 프레임 수 = 머문 시간의 대리값
    caption: str = ""

    @property
    def conf_mean(self) -> float:
        c = self.record.get("confidence") or {}
        vals = [v for v in c.values() if isinstance(v, (int, float))]
        return sum(vals) / len(vals) if vals else 0.0


_IMAGE_KEYS = ("image", "image_path", "file", "filename", "frame", "path", "src")
_ELAPSED_KEYS = ("elapsed", "elapsed_str", "offset", "t", "timestamp", "shot_datetime")


def _find_frame(value: Any, frame_dir: Path) -> Path | None:
    """기록에 적힌 경로/파일명으로 실제 프레임 파일을 찾는다."""
    if not value:
        return None
    p = Path(str(value))
    for cand in (p, frame_dir / p.name):
        if cand.is_file():
            return cand
    # 확장자가 다를 수 있으므로 stem 으로 한 번 더 찾는다.
    hits = sorted(frame_dir.glob(f"{p.stem}.*"))
    return hits[0] if hits else None


def load_records(path: Path, frame_dir: Path) -> list[Scene]:
    """frame_records.json 을 Scene 리스트로 정규화한다.

    평면 구조({...scene, location_type...})와 중첩 구조({"file":..,"record":{..}})
    를 모두 받아들인다. 최상위가 dict 면 값이 리스트인 첫 키를 본문으로 쓴다.
    """
    if not path.is_file():
        sys.exit(f"[에러] 기록 파일을 찾을 수 없습니다: {path}")

    data = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(data, dict):
        for key in ("records", "frames", "frame_records", "items", "data"):
            if isinstance(data.get(key), list):
                data = data[key]
                break
        else:
            lists = [v for v in data.values() if isinstance(v, list)]
            if not lists:
                sys.exit("[에러] JSON 안에서 기록 배열을 찾지 못했습니다.")
            data = lists[0]
    if not isinstance(data, list) or not data:
        sys.exit("[에러] 기록이 비어 있습니다.")

    scenes: list[Scene] = []
    for i, raw in enumerate(data):
        if not isinstance(raw, dict):
            continue
        rec = raw.get("record") if isinstance(raw.get("record"), dict) else raw

        img_val = next((raw.get(k) or rec.get(k) for k in _IMAGE_KEYS
                        if raw.get(k) or rec.get(k)), None)
        elapsed = next((raw.get(k) or rec.get(k) for k in _ELAPSED_KEYS
                        if raw.get(k) or rec.get(k)), "")

        scenes.append(Scene(
            index=i,
            image=_find_frame(img_val, frame_dir),
            elapsed=str(elapsed),
            record=rec,
            meta=raw,
        ))

    # 기록에 파일명이 없으면 frames/ 를 정렬해 순서대로 매칭한다.
    if not any(s.image for s in scenes):
        files = sorted(p for p in frame_dir.glob("*")
                       if p.suffix.lower() in (".jpg", ".jpeg", ".png"))
        if len(files) == len(scenes):
            for s, f in zip(scenes, files):
                s.image = f
            print(f"[안내] 기록에 파일명이 없어 {frame_dir} 정렬 순서로 매칭했습니다.",
                  file=sys.stderr)
        else:
            # files가 0개(frame_dir이 틀렸거나 비어 있음)인 경우도 반드시 여기서 걸려야 한다.
            # 예전엔 elif files: 였어서 0개일 때 경고 없이 조용히 ref 없는 생성으로 넘어갔다.
            print(f"[경고] {frame_dir} 에서 프레임 {len(files)}개 / 기록 {len(scenes)}개 — "
                  f"수가 달라 매칭하지 못했습니다. 참조 없이(--no-ref와 동일하게) 생성됩니다.",
                  file=sys.stderr)

    return scenes


# ============================================================ Stage A: 장면 선정

def _sig(rec: dict[str, Any]) -> tuple[str, str, str, set[str]]:
    return (
        str(rec.get("location_type", "")),
        str(rec.get("weather", "")),
        str(rec.get("time_of_day", "")),
        set(rec.get("objects") or []),
    )


def _changed(a: dict[str, Any], b: dict[str, Any]) -> bool:
    """장면이 바뀌었다고 볼 수 있는지 판정."""
    la, wa, ta, oa = _sig(a)
    lb, wb, tb, ob = _sig(b)
    if (la, wa, ta) != (lb, wb, tb):
        return True
    if oa or ob:                      # 사물 구성이 절반 이상 달라지면 전환으로 본다
        overlap = len(oa & ob) / max(len(oa | ob), 1)
        return overlap < 0.5
    return False


def select_key_scenes(scenes: list[Scene], n: int, min_conf: float = 0.4) -> list[Scene]:
    """판독 가능한 기록만 남기고 장면 전환 지점으로 묶어 대표 N개를 뽑는다."""
    usable = [s for s in scenes
              if not s.record.get("unreadable") and s.conf_mean >= min_conf]
    if not usable:
        # 신뢰도 기준이 너무 엄격했을 수 있으니 unreadable 만 걸러 재시도
        usable = [s for s in scenes if not s.record.get("unreadable")]
    if not usable:
        sys.exit("[에러] 사용할 수 있는 기록이 없습니다 (모두 unreadable).")

    # 연속 프레임을 장면 단위로 묶기
    groups: list[list[Scene]] = [[usable[0]]]
    for s in usable[1:]:
        if _changed(groups[-1][-1].record, s.record):
            groups.append([s])
        else:
            groups[-1].append(s)

    # 각 장면의 대표는 신뢰도가 가장 높은 프레임. weight = 그 장면의 프레임 수
    reps: list[Scene] = []
    for g in groups:
        rep = max(g, key=lambda s: (s.conf_mean, bool(s.image)))
        rep.weight = len(g)
        reps.append(rep)

    print(f"[Stage A] 프레임 {len(scenes)}개 -> 사용 {len(usable)}개 "
          f"-> 장면 {len(reps)}개", file=sys.stderr)

    if len(reps) <= n:
        return reps

    # 시작과 끝은 흐름상 반드시 남긴다. 남은 자리는 균등 간격이 아니라
    # 프레임 수가 많은(=오래 머문) 장면부터 채운다. 스쳐 지나간 구간보다
    # 실제로 머문 구간이 산책의 흐름을 더 잘 대표한다.
    keep = {0, len(reps) - 1} if n >= 2 else {0}
    middle = sorted(range(1, len(reps) - 1),
                    key=lambda i: (-reps[i].weight, -reps[i].conf_mean))
    for i in middle:
        if len(keep) >= n:
            break
        keep.add(i)
    return [reps[i] for i in sorted(keep)]   # 다시 시간순으로


# ============================================================ API 호출

class Gms:
    def __init__(self, api_key: str, timeout: int = 180):
        self.key = api_key
        self.timeout = timeout
        self.session = requests.Session()
        self.total_tokens = 0

    def _post(self, model: str, payload: dict) -> dict:
        res = self.session.post(
            f"{BASE}/models/{model}:generateContent",
            headers={"Content-Type": "application/json", "x-goog-api-key": self.key},
            json=payload,
            timeout=self.timeout,
        )
        if res.status_code in (401, 403):
            sys.exit("[에러] 인증 실패. GMS_KEY 를 확인하세요.")
        if not res.ok:
            sys.exit(f"[에러] {model} HTTP {res.status_code}\n{res.text[:500]}")
        data = res.json()
        self.total_tokens += (data.get("usageMetadata") or {}).get("totalTokenCount", 0)
        return data

    @staticmethod
    def _parts(data: dict) -> list[dict]:
        cands = data.get("candidates")
        if not cands:
            reason = (data.get("promptFeedback") or {}).get("blockReason", "알 수 없음")
            raise RuntimeError(f"응답이 비어 있습니다 (사유: {reason})")
        return (cands[0].get("content") or {}).get("parts") or []

    def text(self, spec: Any, **vars_) -> str:
        """PromptSpec 으로 텍스트 생성."""
        try:
            user = spec.render(**vars_)
        except (KeyError, IndexError) as e:
            # prompts.py 의 템플릿 변수명이 다를 때를 대비한 폴백.
            # 조용히 넘어가면 지시문이 통째로 빠진 채 호출되는 걸 못 알아챈다.
            print(f"[경고] 프롬프트 템플릿 변수 누락({e}). 축약된 입력으로 대체합니다.",
                  file=sys.stderr)
            user = vars_.get("json_lines") or vars_.get("record_json") or ""
        payload: dict[str, Any] = {
            "contents": [{"role": "user", "parts": [{"text": user}]}],
            "generationConfig": {
                "temperature": getattr(spec, "temperature", 0.6),
                "maxOutputTokens": getattr(spec, "max_output_tokens", 512),
            },
        }
        if getattr(spec, "system", None):
            payload["systemInstruction"] = {"parts": [{"text": spec.system}]}
        parts = self._parts(self._post(TEXT_MODEL, payload))
        return "".join(p.get("text", "") for p in parts).strip()

    def image(self, prompt: str, ref: Path | None = None) -> bytes:
        """이미지 생성. ref 를 주면 실제 프레임을 참조한 image-to-image."""
        parts: list[dict[str, Any]] = []
        if ref:
            b64, mime = encode_ref(ref)
            parts.append({"inline_data": {"mime_type": mime, "data": b64}})
        parts.append({"text": prompt})

        payload = {
            "contents": [{"role": "user", "parts": parts}],
            # 이미지 모델은 이 설정이 없으면 텍스트만 돌려준다.
            "generationConfig": {"responseModalities": ["IMAGE"]},
        }
        for p in self._parts(self._post(IMAGE_MODEL, payload)):
            blob = p.get("inlineData") or p.get("inline_data")
            if blob and blob.get("data"):
                return base64.b64decode(blob["data"])
        raise RuntimeError("이미지 파트가 응답에 없습니다. "
                           "responseModalities 지원 여부를 확인하세요.")


def encode_ref(path: Path) -> tuple[str, str]:
    """참조 프레임을 GMS 바디 제한 안에 들어오도록 축소·압축한다."""
    img = Image.open(path)
    if img.mode not in ("RGB", "L"):
        img = img.convert("RGB")
    img.thumbnail((REF_MAX_SIDE, REF_MAX_SIDE))

    for quality in (85, 70, 55, 40, 28):
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=quality)
        raw = buf.getvalue()
        # base64 는 원본의 약 4/3 크기가 된다
        if len(raw) * 4 // 3 <= MAX_INLINE_BYTES:
            return base64.b64encode(raw).decode("ascii"), "image/jpeg"

    # 화질을 다 낮춰도 안 되면 해상도를 한 단계 더 줄인다
    img.thumbnail((512, 512))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=45)
    return base64.b64encode(buf.getvalue()).decode("ascii"), "image/jpeg"


# ============================================================ 프롬프트 조립

def compose_prompt(scene_prompt: str, style: str, styles: dict[str, str],
                   negative: str, builder: Any) -> str:
    """장면 프롬프트 + 스타일 + 네거티브를 하나의 문자열로 만든다.

    스타일/조립 규칙은 prompts.py의 build_image_prompt가 유일한 소스다.
    Gemini 이미지 API에는 negative_prompt 필드가 없으므로 본문에 서술형으로 녹인다.
    """
    try:
        spec = builder(scene_prompt, style=style)
    except KeyError as e:
        sys.exit(f"[에러] {e} (사용 가능: {list(styles)})")
    base = spec.get("prompt", scene_prompt)
    neg = spec.get("negative_prompt", negative)

    return (f"{base}\n\n"
            f"Do not include any of the following: {neg}.\n"
            f"Output the illustration only, with no caption or text in the image.")


# ============================================================ Stage D: 합성

def _font(size: int, path: str | None = None) -> ImageFont.FreeTypeFont:
    for cand in ([path] if path else []) + FONT_CANDIDATES:
        if cand and Path(cand).is_file():
            try:
                return ImageFont.truetype(cand, size)
            except OSError:
                continue
    return ImageFont.load_default()


def _has_korean_font(path: str | None = None) -> bool:
    for cand in ([path] if path else []) + FONT_CANDIDATES:
        if cand and Path(cand).is_file() and "DejaVu" not in cand:
            return True
    return False


def _fit(img: Image.Image, w: int, h: int) -> Image.Image:
    """비율을 유지하며 w x h 를 꽉 채우도록 잘라 맞춘다."""
    src_r, dst_r = img.width / img.height, w / h
    if src_r > dst_r:
        new_w = int(img.height * dst_r)
        img = img.crop(((img.width - new_w) // 2, 0,
                        (img.width + new_w) // 2, img.height))
    else:
        new_h = int(img.width / dst_r)
        img = img.crop((0, (img.height - new_h) // 2,
                        img.width, (img.height + new_h) // 2))
    return img.resize((w, h), Image.LANCZOS)


def compose_storyboard(panels: list[bytes], scenes: list[Scene], out: Path,
                       title: str, layout: str = "row",
                       font_path: str | None = None) -> None:
    """삽화들을 시간순 스토리보드 한 장으로 합성한다."""
    imgs = [Image.open(io.BytesIO(b)).convert("RGB") for b in panels]
    n = len(imgs)
    ph = int(PANEL_W * 3 / 4)

    cols = n if layout == "row" else min(n, (n + 1) // 2 if n > 4 else 2)
    cols = max(cols, 1)
    rows = (n + cols - 1) // cols

    W = MARGIN * 2 + cols * PANEL_W + (cols - 1) * GAP
    H = MARGIN * 2 + TITLE_H + rows * (ph + CAPTION_H) + (rows - 1) * GAP

    canvas = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(canvas)
    f_title = _font(30, font_path)
    f_cap = _font(19, font_path)
    f_sub = _font(15, font_path)

    draw.text((MARGIN, MARGIN), title, font=f_title, fill=FG)

    for i, (img, sc) in enumerate(zip(imgs, scenes)):
        r, c = divmod(i, cols)
        x = MARGIN + c * (PANEL_W + GAP)
        y = MARGIN + TITLE_H + r * (ph + CAPTION_H + GAP)

        canvas.paste(_fit(img, PANEL_W, ph), (x, y))
        draw.rectangle([x, y, x + PANEL_W - 1, y + ph - 1], outline=(225, 222, 216))

        cap = sc.caption or sc.record.get("location_type", "") or f"장면 {i + 1}"
        draw.text((x + 2, y + ph + 8), f"{i + 1}. {cap}", font=f_cap, fill=FG)
        if sc.elapsed:
            draw.text((x + 2, y + ph + 32), sc.elapsed, font=f_sub, fill=SUB)

        # 같은 행의 칸 사이에 진행 방향 화살표
        if c < cols - 1 and i < n - 1:
            ax, ay = x + PANEL_W + GAP // 2, y + ph // 2
            draw.line([(ax - 4, ay), (ax + 4, ay)], fill=SUB, width=2)
            draw.line([(ax + 1, ay - 4), (ax + 5, ay), (ax + 1, ay + 4)],
                      fill=SUB, width=2)

    canvas.save(out)


# ============================================================ main

def _walk_meta(scenes: list[Scene]) -> tuple[str, str]:
    """기록에서 날짜와 총 소요시간을 추정한다.

    shot_datetime 은 record 안이 아니라 최상위에 있을 수 있으므로 둘 다 본다.
    """
    date_ = ""
    for s in scenes:
        pools = [s.record, s.meta or {}]
        cands = [d.get("shot_datetime") or d.get("date") or d.get("datetime")
                 for d in pools] + [s.elapsed]
        for v in cands:
            m = re.search(r"\d{4}[-/.]\d{2}[-/.]\d{2}", str(v or ""))
            if m:
                date_ = m.group().replace("/", "-").replace(".", "-")
                break
        if date_:
            break
    duration = next((s.elapsed for s in reversed(scenes) if s.elapsed), "")
    return date_, duration


def main() -> None:
    ap = argparse.ArgumentParser(description="산책 흐름 삽화 생성")
    ap.add_argument("--frames", type=Path, default=DEFAULT_FRAME_DIR)
    ap.add_argument("--records", type=Path, default=DEFAULT_RECORDS)
    ap.add_argument("-o", "--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("-n", "--scenes", type=int, default=4, help="대표 장면 수")
    ap.add_argument("--style", default=P.DEFAULT_IMAGE_STYLE,
                    choices=list(P.IMAGE_STYLES), help="prompts.py IMAGE_STYLES 키")
    ap.add_argument("--mode", choices=("storyboard", "single"), default="storyboard")
    ap.add_argument("--layout", choices=("row", "grid"), default="row")
    ap.add_argument("--no-ref", action="store_true",
                    help="실제 프레임을 참조하지 않고 텍스트만으로 생성")
    ap.add_argument("--no-caption-llm", action="store_true",
                    help="캡션을 LLM 대신 location_type 으로 채움")
    ap.add_argument("--font", default=None, help="한국어 TTF 경로")
    ap.add_argument("--dry-run", action="store_true",
                    help="API 호출 없이 장면 선정 결과와 프롬프트만 출력")
    args = ap.parse_args()

    scene_spec, flow_spec, cap_spec, styles, negative, builder = load_prompts()

    scenes = load_records(args.records, args.frames)
    keys = select_key_scenes(scenes, args.scenes)
    walk_date, duration = _walk_meta(scenes)

    if not _has_korean_font(args.font):
        print("[경고] 한국어 폰트를 찾지 못해 캡션이 깨질 수 있습니다. "
              "--font 로 TTF 경로를 지정하세요.", file=sys.stderr)

    if args.dry_run:
        print(f"\n선정된 장면 {len(keys)}개 (날짜={walk_date or '?'}, 소요={duration or '?'})")
        for i, s in enumerate(keys, 1):
            r = s.record
            print(f"  {i}. [{s.elapsed or '-'}] {r.get('location_type', '?')} / "
                  f"{r.get('weather', '?')} / conf={s.conf_mean:.2f} / "
                  f"ref={s.image.name if s.image else '없음'}")
            print(f"     objects={r.get('objects') or []} "
                  f"atmosphere={r.get('atmosphere') or []}")
        return

    api_key = os.environ.get("GMS_KEY")
    if not api_key:
        sys.exit('[에러] 환경변수 GMS_KEY 가 없습니다.\n  export GMS_KEY="발급받은_키"')
    gms = Gms(api_key)
    PANEL_DIR.mkdir(exist_ok=True)

    # ---- single 모드: 산책 전체를 한 장으로 -------------------------------
    if args.mode == "single":
        lines = json.dumps([s.record for s in keys], ensure_ascii=False, indent=1)
        print("[Stage B] 전체 흐름 프롬프트 작성...", file=sys.stderr)
        scene_prompt = gms.text(flow_spec, json_lines=lines, walk_date=walk_date or "미상",
                                duration=duration or "미상", n_scenes=len(keys))
        prompt = compose_prompt(scene_prompt, args.style, styles, negative, builder)
        print(f"  -> {scene_prompt[:120]}...", file=sys.stderr)

        print("[Stage C] 삽화 생성...", file=sys.stderr)
        ref = None if args.no_ref else next((s.image for s in keys if s.image), None)
        args.out.write_bytes(gms.image(prompt, ref))
        print(f"\n완료: {args.out}  [토큰 합계 {gms.total_tokens}]")
        return

    # ---- storyboard 모드 --------------------------------------------------
    panels: list[bytes] = []
    for i, s in enumerate(keys, 1):
        rec_json = json.dumps(s.record, ensure_ascii=False)

        print(f"[Stage B] {i}/{len(keys)} 프롬프트 작성...", file=sys.stderr)
        scene_prompt = gms.text(scene_spec, json_lines=rec_json, record_json=rec_json,
                                walk_date=walk_date or "미상",
                                duration=duration or "미상", n_frames=1,
                                focus=f"panel {i}/{len(keys)} — this single scene only, "
                                      "not the whole walk")
        prompt = compose_prompt(scene_prompt, args.style, styles, negative, builder)

        print(f"[Stage C] {i}/{len(keys)} 삽화 생성"
              f"{'' if args.no_ref or not s.image else f' (참조: {s.image.name})'}...",
              file=sys.stderr)
        png = gms.image(prompt, None if args.no_ref else s.image)
        (PANEL_DIR / f"panel_{i:02d}.png").write_bytes(png)
        panels.append(png)

        if args.no_caption_llm:
            s.caption = s.record.get("location_type", "")
        else:
            s.caption = gms.text(cap_spec, record_json=rec_json,
                                 json_lines=rec_json)[:20]

    print("[Stage D] 스토리보드 합성...", file=sys.stderr)
    title = f"{walk_date + ' ' if walk_date else ''}산책 흐름"
    compose_storyboard(panels, keys, args.out, title, args.layout, args.font)

    print(f"\n완료: {args.out}")
    print(f"개별 삽화: {PANEL_DIR}/  [토큰 합계 {gms.total_tokens}]")


if __name__ == "__main__":
    main()