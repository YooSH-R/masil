"""stages 검증. 가짜 클라이언트를 꽂아 API 없이 돌린다.

무게중심 셋.
  1. 재시도 판단이 옳은가 (retryable만 다시 시도, 나머지는 즉시 포기)
  2. shot_datetime 이 실제로 프롬프트까지 도달하는가
  3. 장면 선정이 레거시와 같은 결과를 내는가
"""

from __future__ import annotations

import base64
import io
import json
from pathlib import Path

import pytest
from PIL import Image

from walklog import prompts as P
from walklog.gms import GMSAuthError, GMSHTTPError, GMSNetworkError
from walklog.records import FrameMeta, FrameRecord, WalkInfo, iter_frames
from walklog.stages import (
    ComposeError,
    IllustrateError,
    KeyScene,
    compose_storyboard,
    compose_walk_log,
    observe_frames,
    scene_changed,
    select_key_scenes,
)

REAL_NAMES = [
    "f_0000128_t000m08.53s.jpg",
    "f_0000160_t000m10.67s.jpg",
    "f_0000448_t000m29.87s.jpg",
    "f_0000960_t001m04.00s.jpg",
    "f_0001605_t001m47.00s.jpg",
]


def touch_frames(directory, names=REAL_NAMES):
    directory.mkdir(parents=True, exist_ok=True)
    for name in names:
        # 실제 JPEG를 만든다. imaging이 파일을 열 수 있어야 한다.
        Image.new("RGB", (32, 24), (100, 120, 140)).save(directory / name, "JPEG")
    return directory


def observation(**over):
    base = {"scene": "젖은 보도블록", "location_type": "공원", "surface": "보도블록",
            "time_of_day": "낮", "weather": "비", "objects": ["가로등", "벤치"],
            "atmosphere": ["한적함"], "unreadable": False,
            "confidence": {"time_of_day": 0.8, "weather": 0.9, "location_type": 0.7}}
    base.update(over)
    return base


class FakeClient:
    """GMSClient 자리에 꽂는다. 호출 내용을 기록하고 정해진 값을 돌려준다."""

    def __init__(self, *, json_results=None, text_results=None,
                 image_results=None, errors=None):
        self.json_results = list(json_results or [])
        self.text_results = list(text_results or [])
        self.image_results = list(image_results or [])
        self.errors = list(errors or [])
        self.calls: list[dict] = []
        self.total_tokens = 0

    def _record(self, kind, spec, kwargs):
        self.calls.append({"kind": kind, "spec": spec, "kwargs": kwargs})

    def _maybe_raise(self):
        if self.errors:
            error = self.errors.pop(0)
            if error is not None:
                raise error

    def generate_json(self, spec, **kwargs):
        self._record("json", spec, kwargs)
        self._maybe_raise()
        return self.json_results.pop(0) if self.json_results else observation()

    def generate_text(self, spec, **kwargs):
        self._record("text", spec, kwargs)
        self._maybe_raise()
        return self.text_results.pop(0) if self.text_results else "결과 텍스트"

    def generate_image(self, prompt, **kwargs):
        self._record("image", prompt, kwargs)
        self._maybe_raise()
        if self.image_results:
            return self.image_results.pop(0)
        return _png_bytes()


def _png_bytes(size=(64, 48), color=(180, 200, 160)):
    buffer = io.BytesIO()
    Image.new("RGB", size, color).save(buffer, "PNG")
    return buffer.getvalue()


# ============================================================ Stage 1

def test_prompt_vars_reach_the_call(tmp_path):
    """shot_datetime / location 이 실제 호출까지 도달하는지.

    분할 전 main()은 describe_frame(f)만 불러서 두 값이 항상 "불명"이었다.
    프롬프트의 time_of_day 우선 지시가 한 번도 발동하지 않은 원인이다.
    """
    walk = WalkInfo(started_at="2026-07-28T08:12:03", location="OO천 산책로")
    metas = iter_frames(touch_frames(tmp_path / "f", REAL_NAMES[:2]), walk=walk)
    client = FakeClient()

    records, failures = observe_frames(client, metas, sleep=lambda _: None)

    assert not failures and len(records) == 2
    first = client.calls[0]["kwargs"]
    assert first["shot_datetime"] == "2026-07-28 08:12:11"
    assert first["location"] == "OO천 산책로"
    assert first["elapsed"] == "0분 9초"
    assert first["image_paths"] == [metas[0].path]
    assert client.calls[0]["spec"] is P.FRAME_EXTRACT


def test_retries_on_retryable_error(tmp_path):
    """429는 다시 보내면 풀릴 수 있다. 프레임을 버리지 않는다."""
    metas = iter_frames(touch_frames(tmp_path / "f", REAL_NAMES[:1]))
    client = FakeClient(errors=[GMSHTTPError(429, "rate limit", "m"), None])
    slept: list[float] = []

    records, failures = observe_frames(client, metas, sleep=slept.append)

    assert len(records) == 1 and not failures
    assert len(client.calls) == 2
    assert slept == [2.0]


def test_gives_up_after_max_attempts(tmp_path):
    metas = iter_frames(touch_frames(tmp_path / "f", REAL_NAMES[:1]))
    client = FakeClient(errors=[GMSHTTPError(503, "down", "m")] * 3)

    records, failures = observe_frames(client, metas, sleep=lambda _: None)

    assert not records and len(failures) == 1
    assert failures[0].attempts == 3
    assert len(client.calls) == 3


@pytest.mark.parametrize("error", [
    GMSHTTPError(400, "responseSchema 거부", "m"),
    GMSAuthError("키 오류"),
])
def test_no_retry_on_permanent_error(tmp_path, error):
    """400이나 인증 실패는 다시 보내도 같은 결과다. 즉시 포기한다."""
    metas = iter_frames(touch_frames(tmp_path / "f", REAL_NAMES[:1]))
    client = FakeClient(errors=[error, None, None])

    records, failures = observe_frames(client, metas, sleep=lambda _: None)

    assert not records and len(client.calls) == 1
    assert failures[0].attempts == 1


def test_one_failure_does_not_stop_the_rest(tmp_path):
    """분할 전 동작 유지: 한 프레임 실패로 전체가 멈추지 않는다."""
    metas = iter_frames(touch_frames(tmp_path / "f", REAL_NAMES[:3]))
    client = FakeClient(errors=[None, GMSNetworkError("끊김"),
                                GMSNetworkError("끊김"), GMSNetworkError("끊김"),
                                None])

    records, failures = observe_frames(client, metas, sleep=lambda _: None)

    assert len(records) == 2 and len(failures) == 1
    assert failures[0].meta.name == REAL_NAMES[1]


def test_records_sorted_by_time(tmp_path):
    metas = iter_frames(touch_frames(tmp_path / "f", REAL_NAMES))
    records, _ = observe_frames(FakeClient(), metas, sleep=lambda _: None)
    offsets = [r.meta.offset_seconds for r in records]
    assert offsets == sorted(offsets)


def test_custom_spec_is_used(tmp_path):
    """thinking_budget 실험용 경로."""
    metas = iter_frames(touch_frames(tmp_path / "f", REAL_NAMES[:1]))
    client = FakeClient()
    spec = P.FRAME_EXTRACT.tweak(thinking_budget=0)

    observe_frames(client, metas, spec=spec, sleep=lambda _: None)
    assert client.calls[0]["spec"].thinking_budget == 0


# ============================================================ Stage 2

def make_records(tmp_path, count=3, **over):
    metas = iter_frames(touch_frames(tmp_path / "f", REAL_NAMES[:count]))
    return [FrameRecord(observation=observation(scene=f"장면 {i}", **over), meta=m)
            for i, m in enumerate(metas, 1)]


def test_compose_excludes_unreadable(tmp_path):
    records = make_records(tmp_path, 3)
    records[1].observation["unreadable"] = True
    client = FakeClient(text_results=["## 일지"])

    assert compose_walk_log(client, records, walk_date="2026-07-28") == "## 일지"

    kwargs = client.calls[0]["kwargs"]
    assert kwargs["n_frames"] == 2
    scenes = [json.loads(line)["scene"] for line in kwargs["json_lines"].splitlines()]
    assert scenes == ["장면 1", "장면 3"]


def test_compose_derives_duration(tmp_path):
    """소요시간을 안 주면 마지막 프레임의 경과 시각을 쓴다."""
    client = FakeClient()
    compose_walk_log(client, make_records(tmp_path, 4), walk_date="2026-07-28")
    assert client.calls[0]["kwargs"]["duration"] == "1분 4초"


def test_compose_style_selects_spec(tmp_path):
    client = FakeClient()
    compose_walk_log(client, make_records(tmp_path, 1), style="pet")
    assert "반려견" in client.calls[0]["spec"].system


def test_compose_all_unreadable(tmp_path):
    records = make_records(tmp_path, 2, unreadable=True)
    with pytest.raises(ComposeError, match="모두 unreadable"):
        compose_walk_log(FakeClient(), records)


def test_compose_json_lines_have_no_meta(tmp_path):
    client = FakeClient()
    compose_walk_log(client, make_records(tmp_path, 2))
    for line in client.calls[0]["kwargs"]["json_lines"].splitlines():
        parsed = json.loads(line)
        assert "scene" in parsed
        assert not any(k in parsed for k in ("file", "elapsed", "_sort"))


# ============================================================ Stage 3 A

def test_scene_changed_on_location():
    assert scene_changed(observation(location_type="공원"),
                         observation(location_type="하천변"))


def test_scene_unchanged_when_same():
    assert not scene_changed(observation(), observation())


def test_scene_changed_on_object_turnover():
    """사물 구성이 절반 이상 달라지면 전환으로 본다."""
    before = observation(objects=["가로등", "벤치"])
    assert scene_changed(before, observation(objects=["다리", "억새"]))
    # 절반 이상 겹치면 같은 장면
    assert not scene_changed(before, observation(objects=["가로등", "벤치", "자판기"]))


def test_select_groups_consecutive_frames(tmp_path):
    """같은 장면이 이어지면 하나로 묶이고 weight가 프레임 수가 된다."""
    metas = iter_frames(touch_frames(tmp_path / "f", REAL_NAMES))
    records = [
        FrameRecord(observation=observation(location_type="주택가"), meta=metas[0]),
        FrameRecord(observation=observation(location_type="주택가"), meta=metas[1]),
        FrameRecord(observation=observation(location_type="주택가"), meta=metas[2]),
        FrameRecord(observation=observation(location_type="하천변"), meta=metas[3]),
        FrameRecord(observation=observation(location_type="공원"), meta=metas[4]),
    ]
    scenes = select_key_scenes(records, 10)
    assert [s.weight for s in scenes] == [3, 1, 1]
    assert [s.observation["location_type"] for s in scenes] == ["주택가", "하천변", "공원"]


def test_select_keeps_first_last_and_heaviest(tmp_path):
    """N개로 줄일 때 시작/끝은 반드시 남고 나머지는 머문 시간 순."""
    metas = iter_frames(touch_frames(tmp_path / "f", REAL_NAMES))
    kinds = ["주택가", "상가거리", "하천변", "산길", "공원"]
    records = []
    for meta, kind in zip(metas, kinds):
        records.append(FrameRecord(observation=observation(location_type=kind),
                                   meta=meta))
    # 하천변(index 2)에 프레임을 더 붙여 weight를 키운다
    extra_meta = FrameMeta(path=metas[2].path, offset_seconds=30.0)
    records.insert(3, FrameRecord(observation=observation(location_type="하천변"),
                                  meta=extra_meta))

    scenes = select_key_scenes(records, 3)
    picked = [s.observation["location_type"] for s in scenes]
    assert picked[0] == "주택가" and picked[-1] == "공원"
    assert "하천변" in picked


def test_select_prefers_high_confidence_representative(tmp_path):
    metas = iter_frames(touch_frames(tmp_path / "f", REAL_NAMES[:2]))
    low = FrameRecord(observation=observation(
        scene="낮은 신뢰도",
        confidence={"time_of_day": 0.5, "weather": 0.5, "location_type": 0.5}),
        meta=metas[0])
    high = FrameRecord(observation=observation(
        scene="높은 신뢰도",
        confidence={"time_of_day": 0.9, "weather": 0.9, "location_type": 0.9}),
        meta=metas[1])

    scenes = select_key_scenes([low, high], 1)
    assert scenes[0].observation["scene"] == "높은 신뢰도"


def test_select_falls_back_when_confidence_too_low(tmp_path):
    """신뢰도 기준이 너무 엄격하면 unreadable만 걸러 재시도한다."""
    records = make_records(tmp_path, 2, confidence={"weather": 0.1})
    scenes = select_key_scenes(records, 2)
    assert len(scenes) >= 1


def test_select_all_unreadable(tmp_path):
    records = make_records(tmp_path, 2, unreadable=True)
    with pytest.raises(IllustrateError, match="모두 unreadable"):
        select_key_scenes(records, 2)


# ============================================================ Stage 3 D

def test_compose_storyboard_row_layout(tmp_path):
    metas = iter_frames(touch_frames(tmp_path / "f", REAL_NAMES[:3]))
    scenes = []
    for i, meta in enumerate(metas, 1):
        record = FrameRecord(observation=observation(), meta=meta,
                             caption=f"캡션 {i}")
        scenes.append(KeyScene(record=record, panel=_png_bytes()))

    out = compose_storyboard(scenes, tmp_path / "out" / "walk_flow.png",
                             title="2026-07-28 산책 흐름", layout="row")

    assert out.is_file()
    image = Image.open(out)
    # 가로 배치: 칸 3개가 한 행에 놓인다
    assert image.width > image.height
    assert image.width == 24 * 2 + 3 * 512 + 2 * 14


def test_compose_storyboard_grid_layout(tmp_path):
    metas = iter_frames(touch_frames(tmp_path / "f", REAL_NAMES))
    scenes = [KeyScene(record=FrameRecord(observation=observation(), meta=m),
                       panel=_png_bytes()) for m in metas]

    out = compose_storyboard(scenes, tmp_path / "grid.png",
                             title="산책 흐름", layout="grid")
    grid = Image.open(out)
    row = Image.open(compose_storyboard(scenes, tmp_path / "row.png",
                                        title="산책 흐름", layout="row"))
    assert grid.width < row.width      # 여러 행으로 접힌다


def test_compose_storyboard_without_panels(tmp_path):
    metas = iter_frames(touch_frames(tmp_path / "f", REAL_NAMES[:1]))
    scenes = [KeyScene(record=FrameRecord(observation=observation(), meta=metas[0]))]
    with pytest.raises(IllustrateError, match="합성할 삽화가 없습니다"):
        compose_storyboard(scenes, tmp_path / "x.png", title="t")


def test_caption_falls_back_to_location_type(tmp_path):
    """캡션이 비어 있으면 location_type을 쓴다."""
    metas = iter_frames(touch_frames(tmp_path / "f", REAL_NAMES[:1]))
    scene = KeyScene(record=FrameRecord(observation=observation(location_type="하천변"),
                                        meta=metas[0]))
    assert scene.caption == "하천변"


def test_reference_is_none_when_file_missing():
    """기록에 적힌 프레임이 실제로 없으면 참조 없이 생성한다."""
    scene = KeyScene(record=FrameRecord(
        observation=observation(), meta=FrameMeta(path=Path("없는파일.jpg"))))
    assert scene.reference is None