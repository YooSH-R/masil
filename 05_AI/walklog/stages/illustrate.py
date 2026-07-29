"""Stage 3 - 관찰 기록 -> 삽화 -> 스토리보드.

  A. 장면 전환 감지 -> 대표 프레임 N개 선정      (로컬, API 없음)
  B. 각 장면 -> 영어 이미지 프롬프트              (LLM)
  C. 각 장면 -> 삽화                              (이미지 모델)
  D. 삽화들 -> 스토리보드 한 장                   (로컬, Pillow)

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
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Sequence

from PIL import Image, ImageDraw, ImageFont

from .. import config
from .. import prompts as P
from ..console import step, warn
from ..gms import GMSClient
from ..records import UNKNOWN, FrameRecord, to_json_lines, usable, walk_duration

__all__ = [
    "IllustrateError",
    "KeyScene",
    "scene_changed",
    "select_key_scenes",
    "write_scene_prompt",
    "write_flow_prompt",
    "render_panel",
    "write_caption",
    "compose_storyboard",
    "build_storyboard",
    "build_single_image",
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


# ============================================================ B. 프롬프트 작성

def write_scene_prompt(
    client: GMSClient,
    scene: KeyScene,
    *,
    position: int,
    total: int,
    style: str = P.DEFAULT_IMAGE_STYLE,
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
    return P.build_image_request(english, style=style)


def write_flow_prompt(
    client: GMSClient,
    scenes: Sequence[KeyScene],
    *,
    walk_date: str = UNKNOWN,
    duration: str = UNKNOWN,
    style: str = P.DEFAULT_IMAGE_STYLE,
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
    return P.build_image_request(english, style=style)


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

    for position, scene in enumerate(scenes, 1):
        step(f"[Stage B] {position}/{total} 프롬프트 작성")
        scene.prompt = write_scene_prompt(client, scene, position=position,
                                          total=total, style=style)

        reference = scene.reference if use_reference else None
        step(f"[Stage C] {position}/{total} 삽화 생성"
             f"{f' (참조: {reference.name})' if reference else ''}")
        scene.panel = render_panel(client, scene, scene.prompt,
                                   use_reference=use_reference, position=position)

        if panel_dir:
            directory = Path(panel_dir)
            directory.mkdir(parents=True, exist_ok=True)
            (directory / f"panel_{position:02d}.png").write_bytes(scene.panel)

        if use_caption_llm:
            scene.record.caption = write_caption(client, scene, position=position)
        else:
            scene.record.caption = scene.observation.get("location_type", "")

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
        style=style,
    )

    step("[Stage C] 삽화 생성")
    reference = next((s.reference for s in scenes if s.reference), None) \
        if use_reference else None
    data = client.generate_image(prompt, reference=reference, tag="flow_image")

    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(data)
    return out