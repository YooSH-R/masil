"""Stage 3 - 관찰 기록 -> 삽화 -> 스토리보드 / 저널 / 패널.

  A. 장면 전환 감지 -> 대표 프레임 N개 선정      (로컬, API 없음)
  A'. 이벤트 중요도 -> 대표 프레임 N개 선정      (로컬, API 없음. 저널/패널 전용)
  B. 각 장면 -> 영어 이미지 프롬프트              (LLM)
  C. 각 장면 -> 삽화                              (이미지 모델)
  D. 삽화들 -> 스토리보드 한 장 / 저널 한 장       (로컬, Pillow. 패널 모드는 없음)

스토리보드(select_key_scenes)는 "장면 전환"이 기준이고, 저널·패널
(select_key_events)은 "이벤트 중요도"가 기준이다. 서로 다른 산출물이므로
선정 함수를 공유하지 않는다 - 하나를 고치면 둘 다 흔들리는 결합을 피한다.

build_panels(2026-08-06)는 build_journal과 A'~C를 공유하지만 D(보드 합성)가
없다 - 이벤트 삽화 자체가 최종 산출물이다(파이프라인 간소화, run.py 참고).

[분할 전에서 바뀐 점]
1. Scene 클래스가 사라졌다. FrameRecord가 관찰 결과·경과 시각·신뢰도·캡션을
   이미 들고 있으므로, 장면 선정에만 필요한 weight를 KeyScene으로 감쌌다.
2. load_records의 추측 로직이 사라졌다. 키 이름 후보 7개 순회, 평면/중첩 구조
   판별, 파일명이 없으면 개수가 맞을 때 정렬 순서로 매칭하던 폴백까지 전부
   records.py가 형식을 단독 소유하면서 필요 없어졌다.
3. compose_prompt 안에 있던 프롬프트 문장이 prompts.build_image_request로 갔다.
4. sys.exit 대신 예외. 프로세스를 죽일지는 CLI가 판단한다.
"""

from __future__ import annotations

import io
import json
import random
import tempfile
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from statistics import median
from typing import Any, Sequence

from PIL import Image, ImageChops, ImageDraw, ImageFont

from .. import config
from .. import prompts as P
from ..console import step, warn
from ..gms import GMSClient, GMSError
from ..records import (
    UNKNOWN,
    FrameRecord,
    to_json_lines,
    top_subjects,
    usable,
    walk_duration,
)

__all__ = [
    "IllustrateError",
    "KeyScene",
    "scene_changed",
    "select_key_scenes",
    "event_score",
    "select_key_events",
    "write_scene_prompt",
    "write_flow_prompt",
    "render_panel",
    "write_caption",
    "compose_storyboard",
    "compose_journal",
    "build_storyboard",
    "build_single_image",
    "build_story_image",
    "build_journal",
    "build_panels",
]


class IllustrateError(RuntimeError):
    """삽화를 만들 수 없다."""


# 스토리보드 레이아웃. 이 파일에서만 쓰는 튜닝 값이므로 config에 두지 않는다.
PANEL_W = 512
CAPTION_H = 56
TITLE_H = 72
GAP = 14
MARGIN = 24
BG = (250, 249, 246)
FG = (38, 38, 38)
SUB = (120, 120, 120)
BORDER = (225, 222, 216)

# 장면 전환 판정 기준. 사물 구성이 절반 이상 달라지면 전환으로 본다.
OBJECT_OVERLAP_THRESHOLD = 0.5
MIN_SCENE_CONFIDENCE = 0.4


# ============================================================ A. 장면 선정

@dataclass
class KeyScene:
    """대표 장면 하나.

    weight는 이 장면에 속한 프레임 수 = 그 자리에 머문 시간의 대리값이다.
    """

    record: FrameRecord
    weight: int = 1
    prompt: str = ""
    panel: bytes | None = field(default=None, repr=False)

    @property
    def observation(self) -> dict[str, Any]:
        return self.record.observation

    @property
    def confidence_mean(self) -> float:
        return self.record.confidence_mean

    @property
    def elapsed(self) -> str:
        return self.record.meta.elapsed

    @property
    def reference(self) -> Path | None:
        """참조로 쓸 실제 프레임. 파일이 없으면 None."""
        path = self.record.meta.path
        return path if path.is_file() else None

    @property
    def caption(self) -> str:
        return self.record.caption or self.observation.get("location_type", "") or ""


def _signature(observation: dict[str, Any]) -> tuple[str, str, str, set[str]]:
    return (
        str(observation.get("location_type", "")),
        str(observation.get("weather", "")),
        str(observation.get("time_of_day", "")),
        set(observation.get("objects") or []),
    )


def scene_changed(before: dict[str, Any], after: dict[str, Any]) -> bool:
    """장면이 바뀌었다고 볼 수 있는지 판정."""
    loc_a, wx_a, tod_a, obj_a = _signature(before)
    loc_b, wx_b, tod_b, obj_b = _signature(after)
    if (loc_a, wx_a, tod_a) != (loc_b, wx_b, tod_b):
        return True
    if obj_a or obj_b:
        overlap = len(obj_a & obj_b) / max(len(obj_a | obj_b), 1)
        return overlap < OBJECT_OVERLAP_THRESHOLD
    return False


def select_key_scenes(
    records: Sequence[FrameRecord],
    n: int,
    *,
    min_confidence: float = MIN_SCENE_CONFIDENCE,
) -> list[KeyScene]:
    """판독 가능한 기록을 장면 단위로 묶어 대표 N개를 뽑는다."""
    candidates = [r for r in usable(records) if r.confidence_mean >= min_confidence]
    if not candidates:
        # 신뢰도 기준이 너무 엄격했을 수 있으니 unreadable만 걸러 재시도
        candidates = usable(records)
    if not candidates:
        raise IllustrateError(
            f"사용할 수 있는 기록이 없습니다 (전체 {len(records)}개가 모두 unreadable)"
        )

    # 연속 프레임을 장면 단위로 묶기
    groups: list[list[FrameRecord]] = [[candidates[0]]]
    for record in candidates[1:]:
        if scene_changed(groups[-1][-1].observation, record.observation):
            groups.append([record])
        else:
            groups[-1].append(record)

    # 각 장면의 대표는 신뢰도가 가장 높은 프레임. 참조 파일이 있으면 우선한다.
    scenes = [
        KeyScene(record=max(g, key=lambda r: (r.confidence_mean, r.meta.path.is_file())),
                 weight=len(g))
        for g in groups
    ]

    step(f"[Stage A] 프레임 {len(records)}개 -> 사용 {len(candidates)}개 "
         f"-> 장면 {len(scenes)}개")

    if len(scenes) <= n:
        return scenes

    # 시작과 끝은 흐름상 반드시 남긴다. 남은 자리는 균등 간격이 아니라
    # 프레임 수가 많은(=오래 머문) 장면부터 채운다. 스쳐 지나간 구간보다
    # 실제로 머문 구간이 산책의 흐름을 더 잘 대표한다.
    keep = {0, len(scenes) - 1} if n >= 2 else {0}
    middle = sorted(range(1, len(scenes) - 1),
                    key=lambda i: (-scenes[i].weight, -scenes[i].confidence_mean))
    for index in middle:
        if len(keep) >= n:
            break
        keep.add(index)
    return [scenes[i] for i in sorted(keep)]   # 다시 시간순으로


# ============================================================ A'. 이벤트 선정 (저널)

# 이벤트 점수 가중치. 참고 디자인의 우선순위를 반영한다:
# 동물 조우 > 특이사항 > 사람 활동 > 식물 > 사물. 관찰 스키마(FRAME_SCHEMA)를
# 바꾸지 않고 기존 필드만으로 계산한다 - 스키마 변경은 prompt_version을
# 올려야 하고 쌓인 기록과의 호환도 깨지기 때문이다.
EVENT_WEIGHTS = {
    "animal": 5.0,      # animals 항목당
    "notable": 3.0,     # notable이 비어있지 않으면
    "people": 1.5,      # people이 "1" 이상이면
    "plant": 1.0,       # plants 항목당 (최대 2개까지만 가산)
    "object": 0.5,      # objects 항목당 (최대 3개까지만 가산)
}


def event_score(record: FrameRecord) -> float:
    """이 프레임이 '이벤트'로서 얼마나 특별한가.

    confidence_mean을 곱해 저신뢰 관찰(환각 가능성)이 상위에 오는 것을
    누른다. 모든 프레임이 0점일 수 있다(단조로운 산책) - 선정 함수가
    시간 균등 폴백을 갖는 이유다.
    """
    obs = record.observation
    score = 0.0
    score += EVENT_WEIGHTS["animal"] * len(obs.get("animals") or [])
    if (obs.get("notable") or "").strip():
        score += EVENT_WEIGHTS["notable"]
    if obs.get("people") not in (None, "", "없음"):
        score += EVENT_WEIGHTS["people"]
    score += EVENT_WEIGHTS["plant"] * min(len(obs.get("plants") or []), 2)
    score += EVENT_WEIGHTS["object"] * min(len(obs.get("objects") or []), 3)
    return score * max(record.confidence_mean, 0.3)


def _primary_subject(record: FrameRecord) -> str:
    """이 이벤트의 핵심 피사체 한 단어/구. 이미지 프롬프트의 focus에 쓴다.

    event_score와 같은 우선순위(동물 > 특이사항 > 식물)를 따른다.
    아무것도 없으면 location_type으로 폴백한다.
    """
    obs = record.observation
    animals = obs.get("animals") or []
    if animals:
        return str(animals[0])
    notable = (obs.get("notable") or "").strip()
    if notable:
        return notable
    plants = obs.get("plants") or []
    if plants:
        return str(plants[0])
    return str(obs.get("location_type") or "")


def select_key_events(
    records: Sequence[FrameRecord],
    n: int,
    *,
    min_gap_ratio: float = 0.5,
) -> list[KeyScene]:
    """점수 상위 이벤트 n개를 뽑되 시간축에 퍼뜨린다.

    점수만으로 뽑으면 같은 피사체(예: 오리 가족)의 연속 프레임이 상위를
    독식해 '여러 이벤트'가 아니라 '한 이벤트의 여러 장'이 된다. 그래서
    탐욕 선택에 최소 시간 간격을 건다: 총 시간 / n * min_gap_ratio.

    전부 0점(단조로운 산책)이거나 간격 제약으로 n개를 못 채우면,
    남은 자리는 select_key_scenes(장면 전환 기준)의 결과에서 채운다.
    """
    candidates = [r for r in usable(records) if r.confidence_mean >= MIN_SCENE_CONFIDENCE]
    if not candidates:
        candidates = usable(records)
    if not candidates:
        raise IllustrateError(
            f"사용할 수 있는 기록이 없습니다 (전체 {len(records)}개가 모두 unreadable)"
        )

    timed = [r.meta.offset_seconds for r in candidates if r.meta.offset_seconds is not None]
    span = (max(timed) - min(timed)) if timed else 0.0
    min_gap = (span / n * min_gap_ratio) if (span > 0 and n > 0) else 0.0

    scored = sorted(candidates, key=event_score, reverse=True)

    chosen: list[FrameRecord] = []
    for record in scored:
        if len(chosen) >= n:
            break
        offset = record.meta.offset_seconds
        if offset is not None and min_gap > 0:
            too_close = any(
                c.meta.offset_seconds is not None
                and abs(c.meta.offset_seconds - offset) < min_gap
                for c in chosen
            )
            if too_close:
                continue
        chosen.append(record)

    if len(chosen) < n:
        chosen_ids = {id(r) for r in chosen}
        for scene in select_key_scenes(records, n):
            if len(chosen) >= n:
                break
            if id(scene.record) in chosen_ids:
                continue
            chosen.append(scene.record)
            chosen_ids.add(id(scene.record))

    chosen.sort(key=lambda r: r.meta.sort_key)
    events = [KeyScene(record=r, weight=round(event_score(r))) for r in chosen]

    step(f"[이벤트 선정] 기록 {len(records)}개 -> 이벤트 {len(events)}개 "
         f"(최소 간격 {min_gap:.1f}초)")
    for position, ev in enumerate(events, 1):
        step(f"  {position}. [{ev.elapsed}] score={event_score(ev.record):.1f} "
             f"피사체={_primary_subject(ev.record) or '?'}")

    return events


# ============================================================ B. 프롬프트 작성

def write_scene_prompt(
    client: GMSClient,
    scene: KeyScene,
    *,
    position: int,
    total: int,
    style: str = P.DEFAULT_IMAGE_STYLE,
    use_reference: bool = True,
) -> str:
    """칸 하나에 대한 최종 이미지 프롬프트."""
    import json

    record_json = json.dumps(scene.observation, ensure_ascii=False)
    english = client.generate_text(
        P.IMAGE_PROMPT_WRITER,
        tag=f"scene_prompt_{position}",
        json_lines=record_json,
        focus=(f"panel {position}/{total} — this single scene only, "
               "not the whole walk"),
    )
    return P.build_image_request(english, style=style, with_reference=use_reference)


def write_flow_prompt(
    client: GMSClient,
    scenes: Sequence[KeyScene],
    *,
    walk_date: str = UNKNOWN,
    duration: str = UNKNOWN,
    style: str = P.DEFAULT_IMAGE_STYLE,
    use_reference: bool = True,
) -> str:
    """산책 전체를 한 장으로 요약하는 프롬프트."""
    english = client.generate_text(
        P.FLOW_IMAGE_WRITER,
        tag="flow_prompt",
        json_lines=to_json_lines([s.record for s in scenes]),
        walk_date=walk_date,
        duration=duration,
        n_scenes=len(scenes),
    )
    return P.build_image_request(english, style=style, with_reference=use_reference)


def write_caption(client: GMSClient, scene: KeyScene, *, position: int) -> str:
    """스토리보드 칸에 붙는 12자 이내 한국어 캡션."""
    import json

    text = client.generate_text(
        P.PANEL_CAPTION_WRITER,
        tag=f"caption_{position}",
        record_json=json.dumps(scene.observation, ensure_ascii=False),
    )
    return text.strip().splitlines()[0][:20] if text.strip() else ""


# ============================================================ C. 삽화 생성

def _log_image_generation(out_dir: Path, entry: dict) -> None:
    """이미지 생성 형식을 image_manifest.json에 append한다.

    화풍 드리프트가 재발했을 때, 그 이미지가 정확히 어떤 스타일/참조/프롬프트로
    만들어졌는지가 남아 있지 않으면 원인을 되짚을 수 없다. 그래서 이미지 bytes를
    얻는 모든 지점에서 이 함수를 부른다.

    실패해도 이미지 생성을 막지 않는다(진단 기록이지 차단 장치가 아니다) -
    예외는 warn으로만 남긴다.
    """
    manifest_path = out_dir / config.IMAGE_MANIFEST_NAME
    try:
        if manifest_path.is_file():
            try:
                items = json.loads(manifest_path.read_text(encoding="utf-8"))
                if not isinstance(items, list):
                    raise ValueError("최상위가 배열이 아닙니다")
            except (json.JSONDecodeError, ValueError) as exc:
                warn(f"{manifest_path.name}이 손상되어 새로 시작합니다: {exc}")
                items = []
        else:
            items = []
        items.append(entry)
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(
            json.dumps(items, ensure_ascii=False, indent=2), encoding="utf-8")
    except OSError as exc:
        warn(f"이미지 생성 이력 기록 실패({manifest_path}): {exc}")


def _relative_output(path: Path, base: Path) -> str:
    """manifest의 "output" 필드용 - base(세션 폴더) 기준 상대 경로.

    관계가 성립하지 않으면(호출부가 base 밖의 경로를 줬을 때) 절대 경로
    문자열로 물러난다 - manifest 기록은 실패해서는 안 되는 진단 장치다.
    """
    try:
        return path.relative_to(base).as_posix()
    except ValueError:
        return path.as_posix()


def render_panel(
    client: GMSClient,
    scene: KeyScene,
    prompt: str,
    *,
    use_reference: bool = True,
    position: int = 1,
) -> bytes:
    """삽화 한 장. use_reference면 실제 프레임을 참조하는 image-to-image."""
    reference = scene.reference if use_reference else None
    return client.generate_image(prompt, reference=reference,
                                 tag=f"panel_{position}")


# ============================================================ D. 합성

def _font(size: int, path: str | None = None) -> ImageFont.FreeTypeFont:
    for candidate in ([path] if path else []) + list(config.FONT_CANDIDATES):
        if candidate and Path(candidate).is_file():
            try:
                return ImageFont.truetype(candidate, size)
            except OSError:
                continue
    return ImageFont.load_default()


def has_korean_font(path: str | None = None) -> bool:
    """한글 글리프가 있는 폰트를 찾을 수 있는지."""
    for candidate in ([path] if path else []) + list(config.FONT_CANDIDATES):
        if candidate and Path(candidate).is_file() and "DejaVu" not in candidate:
            return True
    return False


def _fit(image: Image.Image, width: int, height: int) -> Image.Image:
    """비율을 유지하며 width x height를 꽉 채우도록 잘라 맞춘다."""
    source_ratio = image.width / image.height
    target_ratio = width / height
    if source_ratio > target_ratio:
        new_width = int(image.height * target_ratio)
        image = image.crop(((image.width - new_width) // 2, 0,
                            (image.width + new_width) // 2, image.height))
    else:
        new_height = int(image.width / target_ratio)
        image = image.crop((0, (image.height - new_height) // 2,
                            image.width, (image.height + new_height) // 2))
    return image.resize((width, height), Image.LANCZOS)


def compose_storyboard(
    scenes: Sequence[KeyScene],
    out: str | Path,
    *,
    title: str,
    layout: str = "row",
    font_path: str | None = None,
) -> Path:
    """삽화들을 시간순 스토리보드 한 장으로 합성한다."""
    panels = [s.panel for s in scenes if s.panel]
    if not panels:
        raise IllustrateError("합성할 삽화가 없습니다")

    images = [Image.open(io.BytesIO(b)).convert("RGB") for b in panels]
    count = len(images)
    panel_h = int(PANEL_W * 3 / 4)

    if layout == "row":
        columns = count
    else:
        columns = min(count, (count + 1) // 2 if count > 4 else 2)
    columns = max(columns, 1)
    rows = (count + columns - 1) // columns

    width = MARGIN * 2 + columns * PANEL_W + (columns - 1) * GAP
    height = (MARGIN * 2 + TITLE_H + rows * (panel_h + CAPTION_H)
              + (rows - 1) * GAP)

    canvas = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(canvas)
    font_title = _font(30, font_path)
    font_caption = _font(19, font_path)
    font_sub = _font(15, font_path)

    draw.text((MARGIN, MARGIN), title, font=font_title, fill=FG)

    for index, (image, scene) in enumerate(zip(images, scenes)):
        row, column = divmod(index, columns)
        x = MARGIN + column * (PANEL_W + GAP)
        y = MARGIN + TITLE_H + row * (panel_h + CAPTION_H + GAP)

        canvas.paste(_fit(image, PANEL_W, panel_h), (x, y))
        draw.rectangle([x, y, x + PANEL_W - 1, y + panel_h - 1], outline=BORDER)

        caption = scene.caption or f"장면 {index + 1}"
        draw.text((x + 2, y + panel_h + 8), f"{index + 1}. {caption}",
                  font=font_caption, fill=FG)
        if scene.elapsed and scene.elapsed != UNKNOWN:
            draw.text((x + 2, y + panel_h + 32), scene.elapsed,
                      font=font_sub, fill=SUB)

        # 같은 행의 칸 사이에 진행 방향 화살표
        if column < columns - 1 and index < count - 1:
            ax, ay = x + PANEL_W + GAP // 2, y + panel_h // 2
            draw.line([(ax - 4, ay), (ax + 4, ay)], fill=SUB, width=2)
            draw.line([(ax + 1, ay - 4), (ax + 5, ay), (ax + 1, ay + 4)],
                      fill=SUB, width=2)

    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out)
    return out


# ============================================================ D'. 저널 합성

# 저널 레이아웃. 스토리보드 상수(PANEL_W 등)와 이름이 겹치지 않도록 JOURNAL_ 접두.
JOURNAL_W = 1620
JOURNAL_H = 2160
JOURNAL_BG = (250, 246, 238)
JOURNAL_HEADER_H = 270
JOURNAL_FOOTER_H = 300
JOURNAL_MARGIN = 48
JOURNAL_CARD_GAP = 36
JOURNAL_CARD_PAD = 24          # 폴라로이드 흰 테두리 패딩
JOURNAL_CARD_CAPTION_H = 84    # 폴라로이드 하단 캡션 영역
JOURNAL_CARD_ROTATE_MAX = 3.0  # 카드 회전 각도(도) 상한
JOURNAL_ACCENT = (196, 106, 94)
JOURNAL_CHIP_BG = (238, 224, 200)
JOURNAL_CHIP_FG = (90, 70, 50)
JOURNAL_NOTE_BG = (250, 224, 224)


def _fit_no_upscale(
    image: Image.Image, width: int, height: int, bg: tuple[int, int, int] = JOURNAL_BG,
) -> Image.Image:
    """비율을 유지하며 width x height 박스 안에 맞춘다. 확대는 하지 않는다.

    이미지 모델 삽화는 보통 1024px급이다. 카드 폭에 맞춰 무조건 리사이즈하면
    (스토리보드의 _fit처럼) 작은 원본을 억지로 키워 흐려질 수 있으므로,
    박스보다 작으면 그대로 두고 가운데에 배치한다(레터박스). 박스보다 크면
    비율을 유지해 축소한다.
    """
    scale = min(width / image.width, height / image.height, 1.0)
    new_w = max(int(image.width * scale), 1)
    new_h = max(int(image.height * scale), 1)
    if scale < 1.0:
        image = image.resize((new_w, new_h), Image.LANCZOS)
    canvas = Image.new("RGB", (width, height), bg)
    canvas.paste(image, ((width - image.width) // 2, (height - image.height) // 2))
    return canvas


def _polaroid_card(
    image: Image.Image,
    width: int,
    height: int,
    *,
    caption: str,
    elapsed: str,
    seed: int,
    font_caption: ImageFont.FreeTypeFont,
    font_sub: ImageFont.FreeTypeFont,
) -> Image.Image:
    """흰 테두리 + 캡션이 붙은 폴라로이드 카드 한 장을 살짝 회전해 반환한다."""
    photo_w = width - JOURNAL_CARD_PAD * 2
    photo_h = height - JOURNAL_CARD_PAD * 2 - JOURNAL_CARD_CAPTION_H

    card = Image.new("RGB", (width, height), (255, 255, 255))
    card.paste(_fit_no_upscale(image, photo_w, photo_h),
               (JOURNAL_CARD_PAD, JOURNAL_CARD_PAD))

    draw = ImageDraw.Draw(card)
    text_y = JOURNAL_CARD_PAD + photo_h + 10
    draw.text((JOURNAL_CARD_PAD, text_y), (caption or "")[:16],
              font=font_caption, fill=FG)
    if elapsed and elapsed != UNKNOWN:
        draw.text((JOURNAL_CARD_PAD, text_y + 34), elapsed, font=font_sub, fill=SUB)

    # 카드마다 고정된 각도로 회전한다(카드 순번을 시드로 써서 재실행해도 같은 모양).
    angle = random.Random(seed).uniform(-JOURNAL_CARD_ROTATE_MAX, JOURNAL_CARD_ROTATE_MAX)
    return card.rotate(angle, expand=True, fillcolor=JOURNAL_BG, resample=Image.BICUBIC)


def compose_journal(
    scenes: Sequence[KeyScene],
    out: str | Path,
    *,
    title: str = "오늘의 산책일지",
    walk_date: str = UNKNOWN,
    time_range: tuple[str, str] | None = None,
    duration: str = UNKNOWN,
    weather: str = UNKNOWN,
    subjects: Sequence[str] = (),
    note: str = "",
    font_path: str | None = None,
) -> Path:
    """이벤트 삽화들을 스크랩북형 산책일지 한 장으로 합성한다. API 호출 없음.

    구성: 헤더(제목/날짜/통계) - 이벤트 카드 2열 그리드(폴라로이드 스타일) -
    하단(오늘 만난 것들 칩 + 한마디). 지도/걸음수/거리처럼 데이터가 없는
    항목은 넣지 않는다 - 그럴듯한 값을 지어내는 것은 관찰 원칙 위반이다.
    """
    panels = [s.panel for s in scenes if s.panel]
    if not panels:
        raise IllustrateError("합성할 삽화가 없습니다")

    canvas = Image.new("RGB", (JOURNAL_W, JOURNAL_H), JOURNAL_BG)
    draw = ImageDraw.Draw(canvas)

    font_title = _font(58, font_path)
    font_date = _font(32, font_path)
    font_stats = _font(30, font_path)
    font_caption = _font(28, font_path)
    font_sub = _font(22, font_path)
    font_label = _font(36, font_path)
    font_chip = _font(26, font_path)
    font_note = _font(28, font_path)

    # ---------------------------------------------------------------- 헤더
    draw.text((JOURNAL_MARGIN, JOURNAL_MARGIN), title, font=font_title, fill=FG)
    if walk_date and walk_date != UNKNOWN:
        draw.text((JOURNAL_MARGIN, JOURNAL_MARGIN + 74), walk_date,
                  font=font_date, fill=JOURNAL_ACCENT)

    stats_parts = [f"날씨: {weather}"]
    if time_range:
        stats_parts.append(f"시간: {time_range[0]}~{time_range[1]}")
    if duration and duration != UNKNOWN:
        stats_parts.append(duration)
    stats_line = "   ".join(stats_parts)
    stats_w = draw.textlength(stats_line, font=font_stats)
    draw.text((JOURNAL_W - JOURNAL_MARGIN - stats_w, JOURNAL_MARGIN + 20),
              stats_line, font=font_stats, fill=FG)

    # ---------------------------------------------------------------- 본문 (카드 그리드)
    images = [Image.open(io.BytesIO(b)).convert("RGB") for b in panels]
    cards_scenes = [s for s in scenes if s.panel]

    columns = 2
    content_top = JOURNAL_HEADER_H
    content_bottom = JOURNAL_H - JOURNAL_FOOTER_H
    area_w = JOURNAL_W - 2 * JOURNAL_MARGIN
    area_h = content_bottom - content_top - JOURNAL_MARGIN
    card_w = (area_w - JOURNAL_CARD_GAP) // columns
    rows = (len(images) + columns - 1) // columns
    row_h = (area_h - (rows - 1) * JOURNAL_CARD_GAP) // max(rows, 1)

    for index, (image, scene) in enumerate(zip(images, cards_scenes)):
        row, column = divmod(index, columns)
        cell_x = JOURNAL_MARGIN + column * (card_w + JOURNAL_CARD_GAP)
        cell_y = content_top + row * (row_h + JOURNAL_CARD_GAP)

        card = _polaroid_card(
            image, card_w, row_h,
            caption=scene.caption or f"장면 {index + 1}",
            elapsed=scene.elapsed, seed=index,
            font_caption=font_caption, font_sub=font_sub,
        )
        # 회전(expand=True)으로 카드가 셀보다 커질 수 있으므로 셀 중심에 맞춘다.
        paste_x = cell_x + (card_w - card.width) // 2
        paste_y = cell_y + (row_h - card.height) // 2
        canvas.paste(card, (paste_x, paste_y))

    # ---------------------------------------------------------------- 하단
    footer_top = JOURNAL_H - JOURNAL_FOOTER_H + JOURNAL_MARGIN // 2
    draw.text((JOURNAL_MARGIN, footer_top), "오늘 만난 것들",
              font=font_label, fill=FG)

    chip_h = 56
    chip_x = JOURNAL_MARGIN
    chip_y = footer_top + 56
    for subject in subjects:
        text = subject[:12]
        text_w = int(draw.textlength(text, font=font_chip))
        chip_w = text_w + 44
        if chip_x + chip_w > JOURNAL_W - JOURNAL_MARGIN and chip_x > JOURNAL_MARGIN:
            chip_x = JOURNAL_MARGIN
            chip_y += chip_h + 16
        draw.rounded_rectangle(
            [chip_x, chip_y, chip_x + chip_w, chip_y + chip_h],
            radius=chip_h // 2, fill=JOURNAL_CHIP_BG,
        )
        draw.text((chip_x + 22, chip_y + 13), text, font=font_chip, fill=JOURNAL_CHIP_FG)
        chip_x += chip_w + 16

    if note:
        note_y = chip_y + chip_h + 24
        note_h = 70
        draw.rounded_rectangle(
            [JOURNAL_MARGIN, note_y, JOURNAL_W - JOURNAL_MARGIN, note_y + note_h],
            radius=22, fill=JOURNAL_NOTE_BG,
        )
        draw.text((JOURNAL_MARGIN + 24, note_y + 20), f"한마디: {note}",
                  font=font_note, fill=FG)

    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out)
    return out


# ============================================================ 조립

def build_storyboard(
    client: GMSClient,
    records: Sequence[FrameRecord],
    out: str | Path,
    *,
    scene_count: int = 4,
    style: str = P.DEFAULT_IMAGE_STYLE,
    layout: str = "row",
    walk_date: str = UNKNOWN,
    use_reference: bool = True,
    use_caption_llm: bool = True,
    panel_dir: str | Path | None = None,
    font_path: str | None = None,
) -> tuple[Path, list[KeyScene]]:
    """장면 선정부터 스토리보드 합성까지 한 번에."""
    scenes = select_key_scenes(records, scene_count)
    total = len(scenes)

    if not has_korean_font(font_path):
        warn("한국어 폰트를 찾지 못해 캡션이 깨질 수 있습니다. "
             f"--font 로 TTF 경로를 지정하거나 {config.FONT_ENV} 를 설정하세요.")

    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)

    for position, scene in enumerate(scenes, 1):
        step(f"[Stage B] {position}/{total} 프롬프트 작성")
        scene.prompt = write_scene_prompt(client, scene, position=position,
                                          total=total, style=style,
                                          use_reference=use_reference)

        reference = scene.reference if use_reference else None
        step(f"[Stage C] {position}/{total} 삽화 생성"
             f"{f' (참조: {reference.name})' if reference else ''}")
        scene.panel = render_panel(client, scene, scene.prompt,
                                   use_reference=use_reference, position=position)

        panel_filename = f"panel_{position:02d}.png"
        if panel_dir:
            directory = Path(panel_dir)
            directory.mkdir(parents=True, exist_ok=True)
            panel_path = directory / panel_filename
            panel_path.write_bytes(scene.panel)
            output_rel = _relative_output(panel_path, out.parent)
        else:
            output_rel = panel_filename
        _log_image_generation(out.parent, {
            "output": output_rel,
            "tag": f"panel_{position}",
            "style": style,
            "style_text": P.IMAGE_STYLES.get(style, ""),
            "with_reference": reference is not None,
            "reference_file": reference.name if reference else None,
            "final_prompt": scene.prompt,
            "model": config.IMAGE_MODEL,
            "attempts": [{"tag": f"panel_{position}", "style_check": None}],
            "created_at": datetime.now().isoformat(timespec="seconds"),
        })

        # 캡션은 장식이다. 여기서 실패했다고 이미 생성한(=이미 과금된) 삽화를
        # 버리면 손해가 크다. 실패하면 경고만 남기고 location_type으로 대체한다.
        fallback = scene.observation.get("location_type", "")
        if use_caption_llm:
            try:
                scene.record.caption = write_caption(client, scene, position=position)
            except GMSError as exc:
                warn(f"{position}번 칸 캡션 생성 실패({exc}). "
                     f"'{fallback}' 로 대체합니다.")
                scene.record.caption = fallback
        else:
            scene.record.caption = fallback

    step("[Stage D] 스토리보드 합성")
    title = f"{walk_date + ' ' if walk_date != UNKNOWN else ''}산책 흐름"
    path = compose_storyboard(scenes, out, title=title, layout=layout,
                              font_path=font_path)
    return path, scenes


def build_single_image(
    client: GMSClient,
    records: Sequence[FrameRecord],
    out: str | Path,
    *,
    scene_count: int = 4,
    style: str = P.DEFAULT_IMAGE_STYLE,
    walk_date: str = UNKNOWN,
    duration: str | None = None,
    use_reference: bool = True,
) -> Path:
    """산책 전체를 한 장으로 요약한 삽화."""
    scenes = select_key_scenes(records, scene_count)

    step("[Stage B] 전체 흐름 프롬프트 작성")
    prompt = write_flow_prompt(
        client, scenes, walk_date=walk_date,
        duration=duration or walk_duration([s.record for s in scenes]),
        style=style, use_reference=use_reference,
    )

    step("[Stage C] 삽화 생성")
    reference = next((s.reference for s in scenes if s.reference), None) \
        if use_reference else None
    data = client.generate_image(prompt, reference=reference, tag="flow_image")

    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(data)

    _log_image_generation(out.parent, {
        "output": _relative_output(out, out.parent),
        "tag": "flow_image",
        "style": style,
        "style_text": P.IMAGE_STYLES.get(style, ""),
        "with_reference": reference is not None,
        "reference_file": reference.name if reference else None,
        "final_prompt": prompt,
        "model": config.IMAGE_MODEL,
        "attempts": [{"tag": "flow_image", "style_check": None}],
        "created_at": datetime.now().isoformat(timespec="seconds"),
    })
    return out


def build_story_image(
    client: GMSClient,
    records: Sequence[FrameRecord],
    story: str,
    out: str | Path,
    *,
    style: str = P.DEFAULT_IMAGE_STYLE,
    use_reference: bool = True,
    verify: bool = False,
    max_regens: int = 2,
    verify_style: bool = True,
) -> Path:
    """이야기의 감정적 핵심 장면을 한 장의 삽화로.

    build_single_image와의 차이: 프롬프트가 기록 요약이 아니라
    이야기(Stage 2 산출물)에서 나온다.
    참조 프레임은 신뢰도가 가장 높은 장면의 것을 쓴다. 표본 추출(4등분
    1장씩) 이후에는 장면당 프레임이 1개라 weight(머문 시간)가 전부 1이
    되어 신호로 쓸 수 없다.

    verify=False(기본)면 이미지 API 호출은 1회이고 그 결과를 그대로 쓴다.

    verify=True면 생성 직후 STORY_IMAGE_VERIFIER로 이미지가 산책 여정
    (장소/시간대/날씨/분위기)을 반영했는지 재검증한다. 불합격이면
    verdict의 fix_hints를 프롬프트에 덧붙여 최대 max_regens회 재생성한다
    (이전 시도의 hint를 누적하지 않고 최신 것만 쓴다). 최대 시도를 다
    써도 전부 불합격이면 이미지를 폐기하지 않고 score가 가장 높은 후보를
    채택한다 - 이미지 생성은 매 시도 과금되므로 전량 폐기는 손해다.
    검증 API 호출 자체가 실패(GMSError)하면 그 시점의 후보를 그대로
    채택한다 - 검증은 품질을 높이는 장치이지 결과를 막는 차단 장치가
    아니다(캡션 생성 실패 시 대체값으로 넘어가는 것과 같은 원칙).

    verify_style=True(기본)면 위 내용 검증 루프가 끝나 최종 채택본이 정해진
    "직후" 그 채택본을 화풍 검증 사다리(_render_with_style_enforcement,
    build_journal의 패널과 같은 헬퍼)에 initial로 넘긴다: 1차 검사 불합격이면
    2차(STRICTLY 강조, 참조 유지), 그래도 불합격이면 3차(참조 제거)까지
    자동 승급한다 - 참조 프레임과 장면 프롬프트가 둘 다 사진 쪽으로 당기면
    텍스트 강조만으로는 못 이기는 경우가 있어(참조 근접샷 등) 마지막 수단으로
    참조 자체를 제거한다. 재생성이 일어나도 내용 검증(STORY_IMAGE_VERIFIER)을
    다시 돌리지 않는다 - 내용 합격 -> 화풍 불합격 -> 재생성 -> 내용 재검증
    -> ... 의 무한 왕복을 막기 위해서다.
    """
    scenes = select_key_scenes(records, 4)

    step("[Stage B] 이야기 핵심 장면 프롬프트 작성")
    english = client.generate_text(
        P.STORY_IMAGE_WRITER,
        tag="story_image_prompt",
        story=story,
        json_lines=to_json_lines([s.record for s in scenes]),
    )

    reference = None
    if use_reference:
        anchored = [s for s in scenes if s.reference]
        if anchored:
            reference = max(anchored, key=lambda s: s.confidence_mean).reference

    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)

    verify_json_lines = to_json_lines([s.record for s in scenes])
    attempts = 1 + max(max_regens, 0)
    candidates: list[dict[str, Any]] = []   # [{"path", "data", "score", "prompt"}, ...]
    attempts_log: list[dict] = []
    hints = ""
    chosen: bytes | None = None
    chosen_prompt = ""

    for attempt in range(1, attempts + 1):
        prompt = P.build_image_request(english, style=style, extra=hints,
                                       with_reference=reference is not None)
        tag = "story_image" if attempt == 1 else f"story_image_retry{attempt - 1}"

        step("[Stage C] 감성 삽화 생성"
             + (f" ({attempt}/{attempts})" if verify else ""))
        data = client.generate_image(prompt, reference=reference, tag=tag)

        if not verify:
            chosen = data
            chosen_prompt = prompt
            attempts_log.append({"tag": tag, "content_check": None})
            break

        candidate_path = out.parent / f"story_image_candidate{attempt}.png"
        candidate_path.write_bytes(data)

        try:
            verdict = client.generate_json(
                P.STORY_IMAGE_VERIFIER,
                image_paths=[candidate_path],
                tag=f"story_image_verify{attempt}",
                json_lines=verify_json_lines,
            )
        except GMSError as exc:
            warn(f"이미지 검증 호출 실패({exc}). 이번 후보를 그대로 사용합니다.")
            candidates.append({"path": candidate_path, "data": data,
                               "score": 0.0, "prompt": prompt})
            attempts_log.append({"tag": tag, "content_check": None})
            chosen = data
            chosen_prompt = prompt
            break

        score = float(verdict.get("score") or 0.0)
        candidates.append({"path": candidate_path, "data": data,
                           "score": score, "prompt": prompt})
        attempts_log.append({"tag": tag, "content_check": {
            "pass": verdict["pass"], "score": score,
            "reasons": verdict.get("reasons") or [],
        }})

        if verdict["pass"]:
            step(f"[검증] {attempt}차 합격 (score={score:.2f})")
            chosen = data
            chosen_prompt = prompt
            break

        reasons = "; ".join(verdict.get("reasons") or [])
        step(f"[검증] {attempt}차 불합격 (score={score:.2f}): {reasons}")
        hints = verdict.get("fix_hints") or ""

    if chosen is None:
        best = max(candidates, key=lambda c: c["score"])
        warn(f"검증을 통과하지 못해 최고 점수 후보를 사용합니다 (score={best['score']:.2f})")
        chosen = best["data"]
        chosen_prompt = best["prompt"]

    chosen, chosen_prompt, style_attempts = _render_with_style_enforcement(
        client, english,
        style=style,
        reference=reference,
        tag_base="story_image",
        verify_style=verify_style,
        initial=chosen,          # 내용 검증이 채택한 이미지를 1차 후보로
    )
    if attempts_log:
        attempts_log[-1]["style_check"] = style_attempts[0]["style_check"]
        attempts_log[-1]["with_reference"] = style_attempts[0]["with_reference"]
        attempts_log[-1]["trimmed"] = style_attempts[0].get("trimmed", False)
    else:
        attempts_log.append(style_attempts[0])
    attempts_log.extend(style_attempts[1:])

    out.write_bytes(chosen)
    for cand in candidates:
        if cand["path"].exists():
            cand["path"].unlink()

    adopted = attempts_log[-1]
    _log_image_generation(out.parent, {
        "output": _relative_output(out, out.parent),
        "tag": adopted["tag"],
        "adopted_tag": adopted["tag"],
        "trimmed": adopted.get("trimmed", False),
        "style": style,
        "style_text": P.IMAGE_STYLES.get(style, ""),
        "with_reference": adopted.get("with_reference", reference is not None),
        "reference_file": reference.name if (reference and adopted.get("with_reference"))
                          else None,
        "final_prompt": chosen_prompt,
        "model": config.IMAGE_MODEL,
        "attempts": attempts_log,
        "created_at": datetime.now().isoformat(timespec="seconds"),
    })
    return out


def _trim_margins(data: bytes, *, tolerance: int = 16,
                  max_trim_ratio: float = 0.25) -> bytes:
    """가장자리의 균일한 종이 여백을 잘라낸다. API 호출 없음, 결정적.

    부정 조건("white borders, paper edges...")은 여백 확률을 낮출 뿐
    보장하지 못함이 2026-08-05 session3에서 재확인됐다(negative를 포함한
    프롬프트에서도 여백이 재발했다). 확률 싸움을 프롬프트에만 맡기지 않고
    후처리로 결정적으로 확정한다.

    안전장치: bbox 크롭이 원본의 (1 - max_trim_ratio)보다 작아지면 여백이
    아니라 그림 내용(밝은 하늘 등)을 자르려는 것으로 보고 원본을 그대로
    반환한다. bbox가 없거나(전체가 배경과 균일) 전체와 같으면(여백 없음)
    원본을 그대로 반환한다.
    """
    image = Image.open(io.BytesIO(data)).convert("RGB")
    width, height = image.size

    corners = [image.getpixel((0, 0)), image.getpixel((width - 1, 0)),
              image.getpixel((0, height - 1)), image.getpixel((width - 1, height - 1))]
    background = tuple(int(median(c[i] for c in corners)) for i in range(3))

    diff = ImageChops.difference(image, Image.new("RGB", image.size, background))
    diff = diff.convert("L").point(lambda p: 255 if p > tolerance else 0)
    bbox = diff.getbbox()

    if bbox is None or bbox == (0, 0, width, height):
        return data     # 여백 없음(또는 판별 불가) - 원본 그대로

    left, top, right, bottom = bbox
    if (right - left) < width * (1 - max_trim_ratio) \
            or (bottom - top) < height * (1 - max_trim_ratio):
        return data      # 안전장치: 과도한 크롭은 여백이 아니라 그림 내용을 자르는 것

    buffer = io.BytesIO()
    image.crop(bbox).save(buffer, "PNG")
    return buffer.getvalue()


def _style_check(client: GMSClient, image: bytes, *, style: str, tag: str
                 ) -> tuple[dict | None, str | None]:
    """PANEL_STYLE_CHECKER를 호출한다. 검사 자체는 차단 장치가 아니므로
    호출이 실패하면 예외를 올리지 않고 (None, 에러 메시지)를 반환한다.

    임시 파일은 시스템 temp에 쓰고 호출 직후 정리한다 - 세션 폴더 경로를
    몰라도(공용 헬퍼라 out_dir을 받지 않는다) 검사할 수 있어야 하기 때문이다.
    """
    fd, tmp_name = tempfile.mkstemp(suffix=".png")
    check_path = Path(tmp_name)
    try:
        with open(fd, "wb") as f:
            f.write(image)
        verdict = client.generate_json(
            P.PANEL_STYLE_CHECKER,
            image_paths=[check_path],
            style_text=P.IMAGE_STYLES[style],
            tag=f"style_check_{tag}",
        )
        return verdict, None
    except GMSError as exc:
        return None, str(exc)
    finally:
        check_path.unlink(missing_ok=True)


def _style_check_passes(verdict: dict) -> bool:
    return (not verdict.get("is_photographic")
            and verdict.get("matches_style", True)
            and not verdict.get("face_visible"))


def _render_with_style_enforcement(
    client: GMSClient,
    english: str,
    *,
    style: str,
    reference: Path | None,
    tag_base: str,
    verify_style: bool = True,
    initial: bytes | None = None,
) -> tuple[bytes, str, list[dict]]:
    """화풍 검증 사다리를 통과한 삽화 한 장을 만든다.

    반환: (채택된 이미지 bytes, 채택본의 최종 프롬프트, attempts 기록)

    initial이 주어지면 1차 생성을 건너뛰고 그것을 1차 후보로 취급한다
    (이미 다른 경로 - 예: 내용 검증 루프 - 에서 생성·과금된 이미지를
    다시 만들지 않기 위해서다). 이때 1차의 "최종 프롬프트"는 english를
    기본 조립한 것으로 기록한다.

    단계 (photoreal 계열이거나 verify_style=False면 1차만, 무검사 채택):
      1차: initial 또는 [참조 포함, 기본 프롬프트 생성]              -> 검사
      2차: 참조 포함, extra=STYLE_EMPHASIS                           -> 검사
      3차: 참조 제거(reference=None, with_reference=False),
           2차와 같은 extra                                         -> 검사

    호출부가 처음부터 reference=None을 넘기면(참조 자체가 없는 무참조 생성 -
    build_panels가 기본으로 쓰는 경로) with_reference=(reference is not None)이
    1차부터 이미 False로 평가되므로 1~3차 전부 참조 없이 조립된다(_REFERENCE_RULE
    미포함). 이 경우 3차는 "참조를 새로 제거"하는 단계가 아니라 2차와 동일한
    조건(참조 없음 + STYLE_EMPHASIS)으로 한 번 더 생성하는 것과 같다 - 단계
    수·비용 상한(이미지 최대 3회)은 그대로다. 2026-08-05 실측(참조 포함 수채화
    생성 7회 중 6회가 화풍 검사 불합격, 전부 3차에서야 합격)이 무참조 기본값의
    근거다.

    각 단계 합격 시 즉시 채택. 합격 판정은 세 조건 모두를 요구한다:
    사진풍이 아니고(is_photographic=False), 화풍이 전체에 균일하게
    적용됐고(matches_style=True), 식별 가능한 얼굴이 없다(face_visible=False).
    셋 중 하나라도 불합격이면 같은 사다리로 승급한다 - face_visible 불합격도
    예외가 아니다. 3차에서는 참조가 제거되고 프롬프트에서도 인물이 배제되므로
    (rules.PRIVACY_EN) 얼굴이 나올 소스 자체가 사라진다.

    3차도 불합격이면 warn 후 3차본을 채택한다 - 참조 없는 텍스트 전용
    생성은 반사진 부정 조건 하에서 사진풍이 나올 확률이 극히 낮고, 빈
    패널은 보드 합성 자체를 깨기 때문이다. 3차 불합격이 face_visible 때문
    이면 별도 사유를 남긴다 - 참조 사진 없이 생성된 3차본의 얼굴은 실존
    인물을 옮겨 그린 것이 아니라 모델이 만들어낸 가공의 얼굴이므로,
    개인정보 위험이 1·2차(실제 참조 인물이 그대로 반영될 위험)보다 낮다는
    것이 채택 근거다.

    검사 호출이 GMSError로 실패하면 그 시점의 후보를 채택한다
    (검증은 차단 장치가 아니다 - 기존 원칙).

    채택 확정 직후, 반환 직전에 _trim_margins로 가장자리 여백을 결정적으로
    제거한다(API 무관, 부정 조건의 확률 방어를 코드로 보강). attempts의
    마지막(=채택된) 항목에 "trimmed" 키로 실제 트림 발생 여부를 남긴다.

    패널당 비용 상한: 이미지 최대 3회 + 검사 최대 3회.
    """
    def finalize(image: bytes, prompt: str) -> tuple[bytes, str, list[dict]]:
        trimmed_image = _trim_margins(image)
        attempts[-1]["trimmed"] = trimmed_image != image
        return trimmed_image, prompt, attempts

    prompt1 = P.build_image_request(english, style=style,
                                    with_reference=reference is not None)
    if initial is not None:
        image1 = initial
    else:
        image1 = client.generate_image(prompt1, reference=reference, tag=tag_base)

    attempts: list[dict] = [
        {"tag": tag_base, "with_reference": reference is not None, "style_check": None},
    ]

    if not verify_style or style in P.PHOTO_STYLES:
        return finalize(image1, prompt1)

    verdict1, err1 = _style_check(client, image1, style=style, tag=tag_base)
    attempts[-1]["style_check"] = verdict1
    if err1 is not None:
        warn(f"[화풍 검사] {tag_base} 검사 실패({err1}). 채택합니다.")
        return finalize(image1, prompt1)
    if _style_check_passes(verdict1):
        step(f"[화풍 검사] {tag_base} 합격")
        return finalize(image1, prompt1)
    step(f"[화풍 검사] {tag_base} 불합격 ({verdict1}) - 2차(강조) 재생성")

    # 2차: 참조 유지 + STRICTLY 강조
    tag2 = f"{tag_base}_restyle"
    prompt2 = P.build_image_request(english, style=style, extra=P.STYLE_EMPHASIS,
                                    with_reference=reference is not None)
    image2 = client.generate_image(prompt2, reference=reference, tag=tag2)
    attempts.append({"tag": tag2, "with_reference": reference is not None, "style_check": None})

    verdict2, err2 = _style_check(client, image2, style=style, tag=tag2)
    attempts[-1]["style_check"] = verdict2
    if err2 is not None:
        warn(f"[화풍 검사] {tag2} 검사 실패({err2}). 채택합니다.")
        return finalize(image2, prompt2)
    if _style_check_passes(verdict2):
        step(f"[화풍 검사] {tag2} 합격")
        return finalize(image2, prompt2)
    step(f"[화풍 검사] {tag2} 불합격 ({verdict2}) - 3차(참조 제거) 재생성")

    # 3차: 참조 제거. 프롬프트 재조립(with_reference=False)과 API 호출
    # (reference=None) 둘 다 바꿔야 한다 - 한쪽만 바꾸면 _REFERENCE_RULE은
    # 빠졌는데 사진은 첨부되거나 그 반대가 되어 프롬프트와 입력이 어긋난다.
    tag3 = f"{tag_base}_noref"
    prompt3 = P.build_image_request(english, style=style, extra=P.STYLE_EMPHASIS,
                                    with_reference=False)
    image3 = client.generate_image(prompt3, reference=None, tag=tag3)
    attempts.append({"tag": tag3, "with_reference": False, "style_check": None})

    verdict3, err3 = _style_check(client, image3, style=style, tag=tag3)
    attempts[-1]["style_check"] = verdict3
    if err3 is not None:
        warn(f"[화풍 검사] {tag3} 검사 실패({err3}). 채택합니다.")
        return finalize(image3, prompt3)
    if _style_check_passes(verdict3):
        step(f"[화풍 검사] {tag3} 합격")
        return finalize(image3, prompt3)

    if verdict3.get("face_visible"):
        warn(f"[화풍 검사] {tag3} 얼굴 노출 판정이지만 참조 없이 생성된 3차본이라 "
             f"실존 인물과 무관한 가공 얼굴로 보고 채택합니다 "
             f"(비용 상한 도달, {verdict3}).")
    else:
        warn(f"[화풍 검사] {tag3} 불합격 ({verdict3})이지만 비용 상한(패널당 이미지 3회)"
             f"에 도달해 그대로 채택합니다.")
    return finalize(image3, prompt3)


def build_journal(
    client: GMSClient,
    records: Sequence[FrameRecord],
    out: str | Path,
    *,
    event_count: int = 4,
    style: str = "journal",
    walk_date: str = UNKNOWN,
    time_range: tuple[str, str] | None = None,
    duration: str = UNKNOWN,
    note: str = "",
    use_reference: bool = True,
    verify_style: bool = True,
    panel_dir: str | Path | None = None,
    font_path: str | None = None,
) -> Path:
    """관찰 기록 -> 이벤트 선정 -> 이벤트별 삽화 -> 스크랩북형 저널 한 장.

    build_storyboard와 같은 골격(선정 -> 프롬프트 -> 삽화 -> 캡션 -> 합성)을
    따르지만 선정 기준이 다르다: 장면 전환이 아니라 이벤트 중요도
    (select_key_events)로 뽑는다. 프롬프트 작성기는 새로 만들지 않고
    기존 IMAGE_PROMPT_WRITER를 재사용하되, focus에 이벤트의 핵심 피사체를
    지시해 그 피사체가 화면의 중심이 되게 한다.

    비용: event_count(기본 4) 기준 LLM 최대 2*event_count회
    (이벤트마다 프롬프트 작성 1회 + 캡션 작성 1회) + verify_style=True면
    패널당 화풍 검사 사다리(_render_with_style_enforcement) 최대 이미지
    3회 + 검사 3회. 지도/걸음수/거리는 만들지 않는다 - 관찰 기록에 없는
    값을 지어내는 것은 "보이는 것만 기록한다"는 프로젝트 원칙 위반이다.

    verify_style=True(기본)면 패널 생성 직후 PANEL_STYLE_CHECKER로 사진풍
    유출/화풍 불일치를 검사한다(style이 PHOTO_STYLES에 속하면 검사 자체를
    건너뛴다 - 사진풍이 그 스타일의 목적이므로). 불합격이면 강조 재생성
    (2차) -> 그래도 불합격이면 참조 제거 재생성(3차)까지 자동 승급한다 -
    어떤 생성물도 검사 없이 채택되지 않는다(3차 최종본이 불합격이어도
    경고와 함께 채택하는 것만 유일한 예외). 프롬프트 강화만으로는 드리프트
    확률을 낮출 뿐 0으로 만들지 못하는데, 저널은 여러 패널이 한 보드에
    나란히 놓여 한 장만 화풍이 달라도 바로 눈에 띄기 때문에 패널마다
    이 사다리를 돈다.

    이벤트 하나의 프롬프트/삽화 생성이 실패해도(GMSError - 일시적 429/5xx,
    네트워크 끊김 등) 그 이벤트만 건너뛰고 나머지로 계속 진행한다. 한 번의
    API 실패로 이미 성공한 나머지 삽화까지 통째로 버리면 손해가 더 크기
    때문이다(observe_frames가 프레임 하나의 실패로 전체를 멈추지 않는 것과
    같은 원칙). 전부 실패하면 IllustrateError를 던진다.
    """
    events = select_key_events(records, event_count)
    total = len(events)

    if not has_korean_font(font_path):
        warn("한국어 폰트를 찾지 못해 캡션이 깨질 수 있습니다. "
             f"--font 로 TTF 경로를 지정하거나 {config.FONT_ENV} 를 설정하세요.")

    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)

    for position, event in enumerate(events, 1):
        focus_subject = _primary_subject(event.record)
        focus = (f"this scene's main subject: {focus_subject} "
                 "(make it the clear focal point)") if focus_subject \
            else "this scene's main subject"

        step(f"[Stage B] {position}/{total} 이벤트 프롬프트 작성 "
             f"(피사체: {focus_subject or '?'})")
        try:
            english = client.generate_text(
                P.IMAGE_PROMPT_WRITER,
                tag=f"journal_prompt_{position}",
                json_lines=json.dumps(event.observation, ensure_ascii=False),
                focus=focus,
            )

            reference = event.reference if use_reference else None
            step(f"[Stage C] {position}/{total} 이벤트 삽화 생성"
                 f"{f' (참조: {reference.name})' if reference else ''}")
            panel, final_prompt, attempts_log = _render_with_style_enforcement(
                client, english,
                style=style,
                reference=reference,
                tag_base=f"panel_{position}",
                verify_style=verify_style,
            )
            event.panel = panel
            event.prompt = final_prompt
        except GMSError as exc:
            warn(f"{position}번 이벤트 삽화 생성 실패({exc}). "
                 f"이 이벤트는 건너뛰고 계속 진행합니다.")
            continue

        panel_filename = f"event_{position:02d}.png"
        if panel_dir:
            directory = Path(panel_dir)
            directory.mkdir(parents=True, exist_ok=True)
            panel_path = directory / panel_filename
            panel_path.write_bytes(event.panel)
            output_rel = _relative_output(panel_path, out.parent)
        else:
            output_rel = panel_filename
        adopted = attempts_log[-1]
        _log_image_generation(out.parent, {
            "output": output_rel,
            "tag": adopted["tag"],
            "adopted_tag": adopted["tag"],
            "trimmed": adopted.get("trimmed", False),
            "style": style,
            "style_text": P.IMAGE_STYLES.get(style, ""),
            "with_reference": adopted.get("with_reference", reference is not None),
            "reference_file": reference.name if (reference and adopted.get("with_reference"))
                              else None,
            "final_prompt": final_prompt,
            "model": config.IMAGE_MODEL,
            "attempts": attempts_log,
            "created_at": datetime.now().isoformat(timespec="seconds"),
        })

        # 캡션은 장식이다. 이미 과금된 삽화를 캡션 실패로 버리지 않는다.
        fallback = event.observation.get("location_type", "")
        try:
            event.record.caption = write_caption(client, event, position=position)
        except GMSError as exc:
            warn(f"{position}번 이벤트 캡션 생성 실패({exc}). '{fallback}' 로 대체합니다.")
            event.record.caption = fallback

    succeeded = [e for e in events if e.panel]
    if not succeeded:
        raise IllustrateError(
            f"이벤트 {total}개 전부 삽화 생성에 실패해 저널을 만들 수 없습니다."
        )
    if len(succeeded) < total:
        warn(f"이벤트 {total}개 중 {len(succeeded)}개만 삽화 생성에 성공했습니다. "
             f"저널은 성공한 {len(succeeded)}개로 만듭니다.")

    usable_records = usable(records)
    weather_counts = Counter(
        r.observation.get("weather") for r in usable_records
        if r.observation.get("weather") and r.observation.get("weather") != UNKNOWN
    )
    weather = weather_counts.most_common(1)[0][0] if weather_counts else UNKNOWN
    subjects = top_subjects(records)

    step(f"[Stage D] 저널 합성 ({len(succeeded)}/{total} 이벤트)")
    return compose_journal(
        succeeded, out,
        walk_date=walk_date, time_range=time_range, duration=duration,
        weather=weather, subjects=subjects, note=note, font_path=font_path,
    )


def build_panels(
    client: GMSClient,
    records: Sequence[FrameRecord],
    panel_dir: str | Path,
    *,
    event_count: int = 4,
    style: str = P.DEFAULT_IMAGE_STYLE,
    use_reference: bool = False,
    verify_style: bool = True,
) -> Path:
    """관찰 기록 -> 이벤트 선정 -> 이벤트별 삽화(panel_dir/event_XX.png)만.

    build_journal과 골격(선정 -> 프롬프트 -> 삽화)은 같지만, 캡션 작성과
    보드 합성(compose_journal)이 없다. 2026-08-05 session4 실측 이후, 이
    파이프라인의 최종 산출물은 이벤트 패널 그 자체이지 Pillow로 합친 보드가
    아니게 됐다 - 캡션은 보드 전용 장식이었으므로 여기서는 이벤트당 LLM 호출을
    1회(프롬프트 작성) 아낀다.

    panel_dir은 호출부가 정한다. flow_image.py의 panels 모드(기본값)는 별도
    하위 폴더 없이 세션 폴더(run_dir)를 그대로 panel_dir로 넘긴다 - 패널이
    유일한 이미지 산출물이라 flow_panels/로 한 단계 더 감쌀 이유가 없다.
    image_manifest.json과 output 상대 경로도 panel_dir 기준이므로, panel_dir이
    세션 폴더 자체면 manifest도 세션 폴더에 곧바로 쓰인다.

    use_reference=False(기본)면 _render_with_style_enforcement에 reference=None을
    넘긴다 - 사다리 1차부터 참조 없이(텍스트 전용) 조립된다. 2026-08-05 실측:
    참조를 붙인 수채화 생성 7회 중 6회가 화풍 검사 불합격이었고, 불합격은 전부
    사다리 3차(참조 제거)에서야 합격했다. 참조를 처음부터 빼면 사다리 비용이
    줄고(대부분 1차 합격) 세트 안 화풍이 참조 유/무로 갈리지 않아 더 균일하다.
    photoreal처럼 참조와 화풍이 싸우지 않는 스타일에서는 호출부가 use_reference=True로
    이 기본을 뒤집을 수 있다.

    이벤트 하나의 프롬프트/삽화 생성이 실패해도(GMSError) 그 이벤트만 건너뛰고
    나머지로 계속 진행한다(build_journal과 같은 원칙). 전부 실패하면
    IllustrateError를 던진다.
    """
    events = select_key_events(records, event_count)
    total = len(events)

    panel_dir = Path(panel_dir)
    panel_dir.mkdir(parents=True, exist_ok=True)

    for position, event in enumerate(events, 1):
        focus_subject = _primary_subject(event.record)
        focus = (f"this scene's main subject: {focus_subject} "
                 "(make it the clear focal point)") if focus_subject \
            else "this scene's main subject"

        step(f"[Stage B] {position}/{total} 이벤트 프롬프트 작성 "
             f"(피사체: {focus_subject or '?'})")
        try:
            english = client.generate_text(
                P.IMAGE_PROMPT_WRITER,
                tag=f"panel_prompt_{position}",
                json_lines=json.dumps(event.observation, ensure_ascii=False),
                focus=focus,
            )

            reference = event.reference if use_reference else None
            step(f"[Stage C] {position}/{total} 이벤트 삽화 생성"
                 f"{f' (참조: {reference.name})' if reference else ''}")
            panel, final_prompt, attempts_log = _render_with_style_enforcement(
                client, english,
                style=style,
                reference=reference,
                tag_base=f"panel_{position}",
                verify_style=verify_style,
            )
            event.panel = panel
            event.prompt = final_prompt
        except GMSError as exc:
            warn(f"{position}번 이벤트 삽화 생성 실패({exc}). "
                 f"이 이벤트는 건너뛰고 계속 진행합니다.")
            continue

        panel_filename = f"event_{position:02d}.png"
        panel_path = panel_dir / panel_filename
        panel_path.write_bytes(event.panel)
        output_rel = _relative_output(panel_path, panel_dir)
        adopted = attempts_log[-1]
        _log_image_generation(panel_dir, {
            "output": output_rel,
            "tag": adopted["tag"],
            "adopted_tag": adopted["tag"],
            "trimmed": adopted.get("trimmed", False),
            "style": style,
            "style_text": P.IMAGE_STYLES.get(style, ""),
            "with_reference": adopted.get("with_reference", reference is not None),
            "reference_file": reference.name if (reference and adopted.get("with_reference"))
                              else None,
            "final_prompt": final_prompt,
            "model": config.IMAGE_MODEL,
            "attempts": attempts_log,
            "created_at": datetime.now().isoformat(timespec="seconds"),
        })

    succeeded = [e for e in events if e.panel]
    if not succeeded:
        raise IllustrateError(
            f"이벤트 {total}개 전부 삽화 생성에 실패해 패널을 만들 수 없습니다."
        )
    if len(succeeded) < total:
        warn(f"이벤트 {total}개 중 {len(succeeded)}개만 삽화 생성에 성공했습니다. "
             f"패널은 성공한 {len(succeeded)}개로 만듭니다.")

    step(f"[완료] 이벤트 패널 {len(succeeded)}/{total}개: {panel_dir}")
    return panel_dir