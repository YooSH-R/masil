"""프레임 파일과 관찰 기록의 형식.

[이 파일이 소유하는 것]
1. 프레임 파일명 규약        f_0000128_t000m08.53s.jpg -> (번호, 경과 초)
2. 프레임 탐색 규약          평면 배치 / seg_XXXX 하위 배치 양쪽
3. 관찰 기록의 자료 구조     FrameRecord
4. frame_records.json 형식   dump_records / load_records
5. Stage 2/3 입력 직렬화     to_json_lines

[분할 전에 흩어져 있던 것]
  walk_log_pipeline: FRAME_RE, parse_frame_meta, to_json_lines,
                     usable 필터(Stage 2와 Stage 3에 중복)
  generate_flow_image: load_records - 키 이름 후보 7개를 순회하고
                     평면/중첩 구조를 추측하고, 파일명이 없으면 개수가 맞을 때
                     정렬 순서로 매칭하는 폴백까지 있었다. 형식을 한 곳에서
                     소유하면 이 추측이 전부 필요 없다.

[바로잡은 버그]
1. 탐색 규약 불일치. main()은 glob("*.jpg")로 평면 배치를 가정했는데
   parse_frame_meta는 path.parent.name을 세그먼트로 써서 seg_XXXX 하위 배치를
   가정했다. 둘 중 하나는 반드시 틀렸다. 이제 iter_frames가 양쪽을 판별한다.
2. 파일명 파싱 실패가 조용했다. _sort=0.0으로 떨어져 정렬이 무너지는데 경고가
   없었다. 순서가 뒤섞인 일지는 그럴듯하게 완성되므로 알아챌 수 없다.
3. shot_datetime이 항상 "불명"이었다. main()이 describe_frame(f)만 호출해서
   프롬프트의 "촬영 일시가 주어졌다면 time_of_day를 그 값으로" 지시가 한 번도
   발동하지 않았다. manifest나 --started-at으로 주면 이제 계산된다.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Iterable, Sequence

from . import config
from .console import warn
from .prompts.vocab import UNKNOWN

__all__ = [
    "UNKNOWN",
    "SCHEMA_VERSION",
    "ManifestError",
    "RecordsError",
    "FRAME_RE",
    "parse_frame_name",
    "format_elapsed",
    "FrameMeta",
    "FrameRecord",
    "WalkInfo",
    "load_manifest",
    "iter_frames",
    "usable",
    "to_json_lines",
    "walk_duration",
    "dump_records",
    "load_records",
]

# frame_records.json 형식 버전. 구조를 바꿀 때 올린다.
SCHEMA_VERSION = 1


class ManifestError(RuntimeError):
    """manifest.json 형식이 예상과 다르다."""


class RecordsError(RuntimeError):
    """frame_records.json을 읽을 수 없다."""


# ============================================================ 파일명 규약

# extract_best_frames.py 가 만드는 이름을 해석한다.
#   f_0000128_t000m08.53s.jpg  ->  프레임 번호 128, 산책 시작 후 8.53초
# 이 정규식이 생산자(추출 스크립트)와 소비자(이 파일) 사이의 계약이다.
# 추출 스크립트에서 이름 형식을 바꾸면 여기도 함께 바꿔야 한다.
FRAME_RE = re.compile(
    r"f_(?P<index>\d+)_t(?P<minutes>\d+)m(?P<seconds>[\d.]+)s"
)


def parse_frame_name(name: str) -> tuple[int, float] | None:
    """파일명에서 (프레임 번호, 경과 초)를 뽑는다. 형식이 다르면 None."""
    match = FRAME_RE.search(name)
    if match is None:
        return None
    minutes = int(match.group("minutes"))
    seconds = float(match.group("seconds"))
    return int(match.group("index")), minutes * 60 + seconds


def format_elapsed(offset_seconds: float | None) -> str:
    """경과 초를 프롬프트에 넣을 문자열로. 예: 90.0 -> "1분 30초" """
    if offset_seconds is None:
        return UNKNOWN
    minutes, seconds = divmod(float(offset_seconds), 60)
    return f"{int(minutes)}분 {seconds:.0f}초"


# ============================================================ 산책 단위 정보

@dataclass(frozen=True)
class WalkInfo:
    """산책 한 번에 대한 정보. 프레임마다 반복되지 않는 값들."""

    date: str = UNKNOWN
    started_at: str | None = None   # ISO 8601. 있으면 프레임별 촬영 일시를 계산한다.
    location: str = UNKNOWN

    def shot_datetime(self, offset_seconds: float | None) -> str:
        """산책 시작 시각 + 경과 = 그 프레임의 촬영 일시.

        이 값이 있으면 VLM이 가장 자주 틀리는 시간대 추정을 아예 우회할 수 있다.
        FRAME_EXTRACT의 user_template이 "촬영 일시가 주어졌다면 time_of_day는
        그 값을 우선하고 confidence를 1.0으로 한다"고 지시하고 있다.
        """
        if not self.started_at or offset_seconds is None:
            return UNKNOWN
        try:
            base = datetime.fromisoformat(self.started_at)
        except ValueError:
            warn(f"started_at 형식을 해석할 수 없습니다: {self.started_at!r} "
                 f"(예: 2026-07-28T08:12:03)")
            return UNKNOWN
        return (base + timedelta(seconds=float(offset_seconds))).strftime(
            "%Y-%m-%d %H:%M:%S")


# ============================================================ 프레임 메타

@dataclass(frozen=True)
class FrameMeta:
    """API 호출 전에 파일에서 알 수 있는 것들."""

    path: Path
    segment: str = UNKNOWN
    index: int | None = None
    offset_seconds: float | None = None
    shot_datetime: str = UNKNOWN
    location: str = UNKNOWN

    @property
    def name(self) -> str:
        return self.path.name

    @property
    def elapsed(self) -> str:
        return format_elapsed(self.offset_seconds)

    @property
    def sort_key(self) -> tuple[bool, float, str]:
        """시간순 정렬 키.

        경과 시각을 모르는 프레임은 뒤로 보낸다. 분할 전에는 0.0으로 떨어져
        맨 앞에 왔는데, 그러면 일지의 첫 문단이 엉뚱한 장면으로 시작한다.
        """
        return (self.offset_seconds is None, self.offset_seconds or 0.0, self.name)

    def prompt_vars(self) -> dict[str, str]:
        """FRAME_EXTRACT.user_template에 넣을 변수.

        템플릿 변수명이 등장하는 유일한 곳이다. prompts/frame.py에서 이름을
        바꾸면 여기만 고치면 되고, 빠뜨리면 payload 조립 시 KeyError로 즉시 걸린다.
        """
        return {
            "segment": self.segment,
            "elapsed": self.elapsed,
            "shot_datetime": self.shot_datetime,
            "location": self.location,
        }


# ============================================================ 관찰 기록

@dataclass
class FrameRecord:
    """프레임 하나에 대한 관찰 기록.

    분할 전에는 모델이 준 dict에 "_elapsed", "_sort" 같은 내부 키를 섞어 넣고
    to_json_lines가 밑줄로 시작하는 키를 걸러냈다. 규약이 암묵적이어서
    r["_sort"] 오타가 런타임까지 갔다. 이제 관찰 결과와 메타가 분리된다.
    """

    observation: dict[str, Any]
    meta: FrameMeta
    caption: str = ""                       # 스토리보드 칸 캡션 (Stage 3에서 채운다)
    extra: dict[str, Any] = field(default_factory=dict)

    @property
    def unreadable(self) -> bool:
        return bool(self.observation.get("unreadable"))

    @property
    def confidence_mean(self) -> float:
        values = [v for v in (self.observation.get("confidence") or {}).values()
                  if isinstance(v, (int, float))]
        return sum(values) / len(values) if values else 0.0

    def to_dict(self) -> dict[str, Any]:
        """저장용 dict. 메타와 관찰 결과를 분리해 담는다."""
        data: dict[str, Any] = {
            "file": self.meta.name,
            "segment": self.meta.segment,
            "index": self.meta.index,
            "offset_seconds": self.meta.offset_seconds,
            "elapsed": self.meta.elapsed,
            "shot_datetime": self.meta.shot_datetime,
            "location": self.meta.location,
            "observation": self.observation,
        }
        if self.caption:
            data["caption"] = self.caption
        if self.extra:
            data["extra"] = self.extra
        return data

    @classmethod
    def from_dict(cls, data: dict[str, Any], *, frame_dir: Path | None = None
                  ) -> "FrameRecord":
        """to_dict 형식과 분할 전 평면 형식을 모두 읽는다.

        분할 전 형식은 관찰 결과 최상위에 "_elapsed", "_sort"가 섞여 있었다.
        outputs/ 에 이미 쌓인 기록을 계속 읽을 수 있어야 하므로 둘 다 받는다.
        """
        if isinstance(data.get("observation"), dict):
            observation = data["observation"]
            name = data.get("file") or ""
            segment = data.get("segment") or UNKNOWN
            index = data.get("index")
            offset = data.get("offset_seconds")
            shot = data.get("shot_datetime") or UNKNOWN
            location = data.get("location") or UNKNOWN
            caption = data.get("caption", "")
            extra = data.get("extra") or {}
        else:
            # 분할 전 평면 형식: 관찰 결과 + 밑줄 내부 키
            observation = {k: v for k, v in data.items() if not k.startswith("_")}
            name = str(data.get("_file") or data.get("file") or "")
            segment = str(data.get("_segment") or UNKNOWN)
            index = None
            offset = data.get("_sort")
            shot = UNKNOWN
            location = UNKNOWN
            caption = ""
            extra = {}
            if name:
                parsed = parse_frame_name(name)
                if parsed:
                    index, offset = parsed

        path = (frame_dir / name) if (frame_dir and name) else Path(name or "불명")
        meta = FrameMeta(
            path=path,
            segment=segment,
            index=index,
            offset_seconds=None if offset is None else float(offset),
            shot_datetime=shot,
            location=location,
        )
        return cls(observation=observation, meta=meta, caption=caption, extra=extra)


# ============================================================ manifest

def load_manifest(path: str | Path) -> tuple[WalkInfo, dict[str, dict[str, Any]]]:
    """manifest.json을 읽어 (산책 정보, {파일명: 프레임별 값})으로 반환한다.

    기대하는 형식:
        {
          "walk": {"date": "2026-07-28",
                   "started_at": "2026-07-28T08:12:03",
                   "location": "OO천 산책로"},
          "frames": [
            {"file": "f_0000128_t000m08.53s.jpg",
             "offset_seconds": 8.53,
             "segment": "seg_0000",
             "shot_datetime": "2026-07-28T08:12:11"}
          ]
        }
    walk와 frames 모두 선택이며, frames의 각 항목에서 file만 필수다.
    나머지는 파일명 파싱 결과를 덮어쓰는 용도다.

    형식이 다르면 추측하지 않고 예외를 던진다. 분할 전 삽화 스크립트는
    키 이름 후보 7개를 순회하며 추측했는데, 그러면 잘못 맞춰도 조용히 넘어간다.
    """
    path = Path(path)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ManifestError(f"manifest를 찾을 수 없습니다: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ManifestError(f"manifest가 올바른 JSON이 아닙니다: {path} ({exc})") from exc

    if not isinstance(data, dict):
        raise ManifestError(
            f"manifest 최상위는 객체여야 합니다 (현재 {type(data).__name__}). "
            f'기대 형식: {{"walk": {{...}}, "frames": [{{"file": "..."}}]}}'
        )

    walk_raw = data.get("walk") or {}
    if not isinstance(walk_raw, dict):
        raise ManifestError('manifest의 "walk"는 객체여야 합니다')
    walk = WalkInfo(
        date=str(walk_raw.get("date") or UNKNOWN),
        started_at=walk_raw.get("started_at") or None,
        location=str(walk_raw.get("location") or UNKNOWN),
    )

    frames_raw = data.get("frames") or []
    if not isinstance(frames_raw, list):
        raise ManifestError('manifest의 "frames"는 배열이어야 합니다')

    per_file: dict[str, dict[str, Any]] = {}
    for item in frames_raw:
        if not isinstance(item, dict):
            raise ManifestError('manifest의 "frames" 항목은 객체여야 합니다')
        name = item.get("file")
        if not name:
            raise ManifestError('manifest의 "frames" 항목에 "file" 키가 없습니다')
        per_file[Path(str(name)).name] = item

    return walk, per_file


# ============================================================ 프레임 탐색

def _segment_of(path: Path, frame_dir: Path) -> str:
    """프레임이 속한 세그먼트 이름.

    평면 배치(frame_dir 바로 아래)면 세그먼트 개념이 없으므로 "불명"이다.
    분할 전에는 path.parent.name을 그대로 써서 평면 배치일 때
    "sample_image" 같은 폴더 이름이 프롬프트에 들어갔다.
    """
    parent = path.parent.resolve()
    return UNKNOWN if parent == frame_dir.resolve() else path.parent.name


def iter_frames(
    frame_dir: str | Path = config.DEFAULT_FRAME_DIR,
    *,
    manifest: str | Path | None = None,
    walk: WalkInfo | None = None,
    recursive: bool = True,
) -> list[FrameMeta]:
    """프레임을 찾아 시간순 FrameMeta 목록으로 반환한다.

    평면 배치와 seg_XXXX 하위 배치를 모두 지원한다(recursive=True 기본).
    manifest가 있으면 파일명 파싱 결과를 덮어쓴다. 파일명은 형식이 바뀌면
    조용히 깨지지만 manifest는 명시적이므로 있을 때는 그쪽을 신뢰한다.
    """
    frame_dir = Path(frame_dir)
    if not frame_dir.is_dir():
        raise RecordsError(f"프레임 폴더가 없습니다: {frame_dir}")

    per_file: dict[str, dict[str, Any]] = {}
    if manifest is not None:
        manifest_walk, per_file = load_manifest(manifest)
        # 명시적으로 넘긴 walk가 우선한다(CLI 인자가 manifest를 덮어쓸 수 있게).
        walk = walk or manifest_walk
    walk = walk or WalkInfo()

    globber = frame_dir.rglob if recursive else frame_dir.glob
    paths = sorted(
        p for p in globber("*")
        if p.is_file() and p.suffix.lower() in config.IMAGE_SUFFIXES
    )
    if not paths:
        raise RecordsError(
            f"{frame_dir} 아래에서 프레임을 찾지 못했습니다 "
            f"(확장자: {', '.join(config.IMAGE_SUFFIXES)})"
        )

    metas: list[FrameMeta] = []
    unparsed: list[str] = []
    for path in paths:
        override = per_file.get(path.name, {})
        parsed = parse_frame_name(path.name)

        index = override.get("index")
        offset = override.get("offset_seconds")
        if parsed is not None:
            index = index if index is not None else parsed[0]
            offset = offset if offset is not None else parsed[1]
        elif offset is None:
            unparsed.append(path.name)

        segment = override.get("segment") or _segment_of(path, frame_dir)
        shot = override.get("shot_datetime") or walk.shot_datetime(offset)

        metas.append(FrameMeta(
            path=path,
            segment=str(segment),
            index=None if index is None else int(index),
            offset_seconds=None if offset is None else float(offset),
            shot_datetime=str(shot),
            location=str(override.get("location") or walk.location),
        ))

    if unparsed:
        warn(
            f"파일명에서 촬영 시각을 읽지 못한 프레임 {len(unparsed)}개: "
            f"{', '.join(unparsed[:3])}{'...' if len(unparsed) > 3 else ''}. "
            f"기대 형식은 f_0000128_t000m08.53s.jpg 이며, "
            f"해당 프레임은 정렬에서 맨 뒤로 갑니다."
        )

    metas.sort(key=lambda m: m.sort_key)
    return metas


# ============================================================ Stage 2/3 입력

def usable(records: Iterable[FrameRecord]) -> list[FrameRecord]:
    """일지·삽화에 쓸 수 있는 기록만 남긴다.

    분할 전에는 이 한 줄이 write_walk_log와 make_image_prompt에 각각 있었다.
    필터 조건이 바뀌면 한쪽만 고칠 위험이 있었다.
    """
    return [r for r in records if not r.unreadable]


def to_json_lines(records: Sequence[FrameRecord]) -> str:
    """관찰 결과를 한 줄씩 직렬화한다. 메타는 넣지 않는다.

    분할 전 to_json_lines가 밑줄로 시작하는 키를 걸러낸 결과와 같다.
    (Stage 2는 프레임별 시각을 받지 않고 전체 소요시간만 받는다)
    """
    return "\n".join(
        json.dumps(r.observation, ensure_ascii=False) for r in records
    )


def walk_duration(records: Sequence[FrameRecord]) -> str:
    """마지막 프레임의 경과 시각을 산책 소요시간으로 쓴다."""
    for record in reversed(records):
        if record.meta.offset_seconds is not None:
            return record.meta.elapsed
    return UNKNOWN


# ============================================================ 저장 / 불러오기

def dump_records(
    records: Sequence[FrameRecord],
    path: str | Path,
    *,
    walk: WalkInfo | None = None,
    prompt_version: str | None = None,
) -> Path:
    """관찰 기록을 JSON으로 저장한다.

    prompt_version을 함께 남기는 이유: 프롬프트를 몇 주에 걸쳐 손보는 동안
    쌓인 기록들이 서로 비교 불가능한 데이터가 되는 것을 막는다.
    스키마가 바뀌는 변경(예: location_type enum 추가) 이후에는 특히 필요하다.
    """
    path = Path(path)
    payload: dict[str, Any] = {
        "schema": SCHEMA_VERSION,
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "frame_count": len(records),
    }
    if prompt_version:
        payload["prompt_version"] = prompt_version
    if walk is not None:
        payload["walk"] = {
            "date": walk.date,
            "started_at": walk.started_at,
            "location": walk.location,
        }
    payload["records"] = [r.to_dict() for r in records]

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return path


def load_records(
    path: str | Path, *, frame_dir: str | Path | None = None
) -> tuple[list[FrameRecord], WalkInfo]:
    """저장된 관찰 기록을 읽는다.

    두 형식을 받는다.
      1. dump_records 형식: {"schema": 1, ..., "records": [...]}
      2. 분할 전 형식: 관찰 결과 dict의 평면 배열

    분할 전 삽화 스크립트처럼 키 이름을 추측하지는 않는다.
    형식이 둘 중 어느 쪽도 아니면 무엇을 기대하는지 알려주고 실패한다.
    """
    path = Path(path)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise RecordsError(f"기록 파일을 찾을 수 없습니다: {path}") from exc
    except json.JSONDecodeError as exc:
        raise RecordsError(f"기록 파일이 올바른 JSON이 아닙니다: {path} ({exc})") from exc

    walk = WalkInfo()
    if isinstance(data, dict):
        raw = data.get("records")
        if not isinstance(raw, list):
            raise RecordsError(
                f'{path}: "records" 배열이 없습니다. '
                f'dump_records 형식({{"schema": 1, "records": [...]}}) 또는 '
                f"분할 전 평면 배열이어야 합니다."
            )
        walk_raw = data.get("walk") or {}
        if isinstance(walk_raw, dict):
            walk = WalkInfo(
                date=str(walk_raw.get("date") or UNKNOWN),
                started_at=walk_raw.get("started_at") or None,
                location=str(walk_raw.get("location") or UNKNOWN),
            )
    elif isinstance(data, list):
        raw = data
    else:
        raise RecordsError(
            f"{path}: 최상위가 객체나 배열이어야 합니다 (현재 {type(data).__name__})"
        )

    directory = Path(frame_dir) if frame_dir else None
    records = [
        FrameRecord.from_dict(item, frame_dir=directory)
        for item in raw if isinstance(item, dict)
    ]
    if not records:
        raise RecordsError(f"{path}: 읽을 수 있는 기록이 없습니다")

    records.sort(key=lambda r: r.meta.sort_key)
    return records, walk