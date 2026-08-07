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

from walklog import config
from walklog import prompts as P
from walklog.gms import GMSAuthError, GMSHTTPError, GMSNetworkError
from walklog.records import FrameMeta, FrameRecord, WalkInfo, iter_frames
from walklog.stages import (
    ComposeError,
    IllustrateError,
    KeyScene,
    build_journal,
    build_panels,
    build_single_image,
    build_story_image,
    build_storyboard,
    compose_journal,
    compose_storyboard,
    compose_walk_log,
    event_score,
    observe_frames,
    observe_outdoor_frames,
    scene_changed,
    select_key_events,
    select_key_scenes,
)
from walklog.stages.illustrate import (
    JOURNAL_BG,
    JOURNAL_H,
    JOURNAL_W,
    _fit_no_upscale,
    _log_image_generation,
    _render_with_style_enforcement,
    _style_check_passes,
    _trim_margins,
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


# ============================================================ Stage 1 (실내 배제 + 대체 관찰)

def test_observe_outdoor_frames_replaces_indoor_with_nearby_outdoor(tmp_path, capsys):
    """실내 판정 프레임은 시간상 가장 가까운 미사용 프레임으로 1회 대체 관찰된다."""
    metaA = FrameMeta(path=Path("a.jpg"), offset_seconds=10.0)
    metaB = FrameMeta(path=Path("b.jpg"), offset_seconds=12.0)
    client = FakeClient(json_results=[
        observation(indoor=True),    # metaA 관찰 -> 실내
        observation(indoor=False),   # metaB 대체 관찰 -> 야외
    ])

    records = observe_outdoor_frames(client, [metaA], [metaA, metaB])

    assert len(records) == 1
    assert records[0].meta.path == metaB.path
    assert records[0].is_indoor is False
    assert len(client.calls) == 2   # 원본 관찰 1회 + 대체 관찰 1회 (상한)
    assert "실내 판정 -> " in capsys.readouterr().err


def test_observe_outdoor_frames_gives_up_when_replacement_also_indoor(capsys):
    """대체 후보도 실내면 그 슬롯은 포기하고 원본(실내)을 그대로 둔다."""
    metaA = FrameMeta(path=Path("a.jpg"), offset_seconds=10.0)
    metaB = FrameMeta(path=Path("b.jpg"), offset_seconds=12.0)
    client = FakeClient(json_results=[
        observation(indoor=True),   # metaA -> 실내
        observation(indoor=True),   # metaB 대체본도 실내
    ])

    records = observe_outdoor_frames(client, [metaA], [metaA, metaB],
                                     allow_indoor_fallback=True)

    assert len(records) == 1
    assert records[0].meta.path == metaA.path      # 대체 실패, 원본 유지
    assert records[0].is_indoor is True
    assert "포기합니다" in capsys.readouterr().err


def test_observe_outdoor_frames_all_indoor_falls_back_with_warning(capsys):
    """대체 후보가 아예 없어 전부 실내로 남으면, 기본값(fallback=True)은 경고 후
    실내 기록을 포함해 그대로 반환한다 - 기존 테스트 영상이 전부 실내이기 때문."""
    metaA = FrameMeta(path=Path("a.jpg"), offset_seconds=10.0)
    client = FakeClient(json_results=[observation(indoor=True)])

    records = observe_outdoor_frames(client, [metaA], [metaA],
                                     allow_indoor_fallback=True)

    assert len(records) == 1
    assert records[0].is_indoor is True
    assert "실내 기록을 포함해 그대로 진행합니다" in capsys.readouterr().err


def test_observe_outdoor_frames_no_fallback_returns_outdoor_only():
    """allow_indoor_fallback=False면 야외 기록만 반환한다 (0개일 수 있음)."""
    metaA = FrameMeta(path=Path("a.jpg"), offset_seconds=10.0)
    client = FakeClient(json_results=[observation(indoor=True)])

    records = observe_outdoor_frames(client, [metaA], [metaA],
                                     allow_indoor_fallback=False)

    assert records == []


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


# ============================================================ Stage 3 A' (이벤트, 저널)

def test_event_score_orders_by_importance(tmp_path):
    """동물 조우 > 특이사항 > 사물 순으로 점수가 높다."""
    metas = iter_frames(touch_frames(tmp_path / "f", REAL_NAMES[:3]))
    conf = {"time_of_day": 0.8, "weather": 0.8, "location_type": 0.8}
    animal_r = FrameRecord(
        observation=observation(animals=["오리"], notable="", objects=[],
                                plants=[], confidence=conf),
        meta=metas[0])
    notable_r = FrameRecord(
        observation=observation(animals=[], notable="특이한 벽화", objects=[],
                                plants=[], confidence=conf),
        meta=metas[1])
    object_r = FrameRecord(
        observation=observation(animals=[], notable="", objects=["벤치"],
                                plants=[], confidence=conf),
        meta=metas[2])

    assert event_score(animal_r) > event_score(notable_r) > event_score(object_r)


def test_event_score_confidence_decay(tmp_path):
    """저신뢰 동물 기록이 고신뢰 notable 기록보다 낮게 나올 수 있다."""
    metas = iter_frames(touch_frames(tmp_path / "f", REAL_NAMES[:2]))
    low_conf_animal = FrameRecord(
        observation=observation(
            animals=["오리"], notable="", objects=[], plants=[],
            confidence={"time_of_day": 0.2, "weather": 0.2, "location_type": 0.2}),
        meta=metas[0])
    high_conf_notable = FrameRecord(
        observation=observation(
            animals=[], notable="특이한 벽화", objects=[], plants=[],
            confidence={"time_of_day": 0.9, "weather": 0.9, "location_type": 0.9}),
        meta=metas[1])

    assert event_score(low_conf_animal) < event_score(high_conf_notable)


def _offset_names(offsets):
    return [f"f_{i:07d}_t{int(o // 60):03d}m{o % 60:05.2f}s.jpg"
            for i, o in enumerate(offsets)]


def test_select_key_events_avoids_clustering(tmp_path):
    """연속 시각(간격 5초)에 몰린 고점수 프레임 3개는 하나만 뽑히고,
    나머지 자리는 시간상 떨어진 프레임으로 채워진다."""
    offsets = [100, 105, 110, 0, 50, 150, 200, 250, 300]
    metas = iter_frames(touch_frames(tmp_path / "f", _offset_names(offsets)))
    by_offset = {m.offset_seconds: m for m in metas}

    records = []
    for o in (100, 105, 110):   # 클러스터: 전부 동물 조우 (고점수)
        records.append(FrameRecord(observation=observation(animals=["오리"]),
                                   meta=by_offset[o]))
    for o in (0, 50, 150, 200, 250, 300):   # 나머지: 점수 0
        records.append(FrameRecord(
            observation=observation(animals=[], notable="", objects=[], plants=[]),
            meta=by_offset[o]))
    records.sort(key=lambda r: r.meta.sort_key)

    events = select_key_events(records, 4)

    assert len(events) == 4
    picked = sorted(e.record.meta.offset_seconds for e in events)
    cluster_hits = [o for o in picked if 95 <= o <= 115]
    assert len(cluster_hits) == 1   # 클러스터에서 하나만


def test_select_key_events_falls_back_to_scenes_when_gap_constrained(tmp_path):
    """전부 0점이고 두 시간대(간격 1초)에 몰려 있으면, 간격 제약으로 채우지
    못한 자리를 select_key_scenes(장면 전환 기준)의 결과로 채운다."""
    offsets = [100, 101, 102, 103, 200, 201, 202, 203]
    metas = iter_frames(touch_frames(tmp_path / "f", _offset_names(offsets)))
    records = [
        FrameRecord(
            observation=observation(location_type=f"loc{i}", animals=[],
                                    notable="", objects=[], plants=[]),
            meta=m)
        for i, m in enumerate(metas)
    ]

    events = select_key_events(records, 4)

    assert len(events) == 4
    picked = {e.record.meta.offset_seconds for e in events}
    # 순수 간격 그리디만으로는 두 클러스터에서 최대 2개(각 1개씩)만 뽑힌다.
    # 나머지는 select_key_scenes 폴백에서 채워져야 한다.
    extras = {101.0, 102.0, 103.0, 201.0, 202.0, 203.0}
    assert len(picked & extras) >= 1


def test_select_key_events_falls_back_when_confidence_too_low(tmp_path):
    """확신도가 너무 낮으면(select_key_scenes와 같은 기준) unreadable만 걸러 재시도한다."""
    records = make_records(tmp_path, 2, confidence={"weather": 0.1})
    events = select_key_events(records, 2)
    assert len(events) >= 1


def test_select_key_events_all_unreadable(tmp_path):
    records = make_records(tmp_path, 2, unreadable=True)
    with pytest.raises(IllustrateError, match="모두 unreadable"):
        select_key_events(records, 2)


# ============================================================ Stage 3 B/C (with_reference 배선)

_REPAINT = "Completely repaint it"


def test_build_storyboard_passes_use_reference_true(tmp_path):
    records = make_records(tmp_path, 2)
    client = FakeClient()

    _, scenes = build_storyboard(client, records, tmp_path / "sb.png",
                                 scene_count=2, use_reference=True)

    assert all(_REPAINT in s.prompt for s in scenes)


def test_build_storyboard_use_reference_false_omits_repaint(tmp_path):
    records = make_records(tmp_path, 2)
    client = FakeClient()

    _, scenes = build_storyboard(client, records, tmp_path / "sb.png",
                                 scene_count=2, use_reference=False)

    assert not any(_REPAINT in s.prompt for s in scenes)


def test_build_single_image_passes_use_reference_true(tmp_path):
    records = make_records(tmp_path, 2)
    client = FakeClient()

    build_single_image(client, records, tmp_path / "single.png",
                       scene_count=2, use_reference=True)

    image_call = next(c for c in client.calls if c["kind"] == "image")
    assert _REPAINT in image_call["spec"]


def test_build_single_image_use_reference_false_omits_repaint(tmp_path):
    records = make_records(tmp_path, 2)
    client = FakeClient()

    build_single_image(client, records, tmp_path / "single.png",
                       scene_count=2, use_reference=False)

    image_call = next(c for c in client.calls if c["kind"] == "image")
    assert _REPAINT not in image_call["spec"]


def test_build_story_image_repaint_instruction_when_reference_found(tmp_path):
    records = make_records(tmp_path, 2)
    client = FakeClient()

    build_story_image(client, records, "이야기", tmp_path / "story.png",
                      use_reference=True)

    image_call = next(c for c in client.calls if c["kind"] == "image")
    assert _REPAINT in image_call["spec"]


def test_build_story_image_no_repaint_instruction_without_reference(tmp_path):
    records = make_records(tmp_path, 2)
    client = FakeClient()

    build_story_image(client, records, "이야기", tmp_path / "story.png",
                      use_reference=False)

    image_call = next(c for c in client.calls if c["kind"] == "image")
    assert _REPAINT not in image_call["spec"]


def test_build_journal_repaint_instruction_when_event_has_reference(tmp_path):
    records = make_journal_records(tmp_path, 4)
    client = FakeClient()

    build_journal(client, records, tmp_path / "out" / "journal.png",
                  event_count=2, use_reference=True)

    image_calls = [c for c in client.calls if c["kind"] == "image"]
    assert image_calls and all(_REPAINT in c["spec"] for c in image_calls)


def test_build_journal_no_repaint_instruction_when_use_reference_false(tmp_path):
    records = make_journal_records(tmp_path, 4)
    client = FakeClient()

    build_journal(client, records, tmp_path / "out" / "journal.png",
                  event_count=2, use_reference=False)

    image_calls = [c for c in client.calls if c["kind"] == "image"]
    assert image_calls and not any(_REPAINT in c["spec"] for c in image_calls)


def test_build_journal_no_repaint_instruction_when_reference_file_missing(tmp_path):
    """use_reference=True여도 실제 참조 파일이 없는 이벤트는 재해석 지시를 넣지 않는다."""
    metas = [FrameMeta(path=Path(f"없는파일{i}.jpg"), offset_seconds=float(i * 30))
             for i in range(4)]
    records = [FrameRecord(observation=observation(location_type=f"loc{i}"), meta=m)
              for i, m in enumerate(metas)]
    client = FakeClient()

    build_journal(client, records, tmp_path / "out" / "journal.png", event_count=2)

    image_calls = [c for c in client.calls if c["kind"] == "image"]
    assert image_calls and not any(_REPAINT in c["spec"] for c in image_calls)


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


# ============================================================ Stage 3 D' (저널 합성)

def make_journal_scenes(tmp_path, count=4, panel_size=(400, 300)):
    metas = iter_frames(touch_frames(tmp_path / "f", REAL_NAMES[:count]))
    scenes = []
    for i, m in enumerate(metas):
        record = FrameRecord(observation=observation(), meta=m, caption=f"caption{i}")
        scenes.append(KeyScene(record=record, panel=_png_bytes(size=panel_size)))
    return scenes


def test_compose_journal_creates_expected_size(tmp_path):
    scenes = make_journal_scenes(tmp_path)
    out = compose_journal(scenes, tmp_path / "out" / "journal.png",
                          walk_date="2026-08-04", time_range=("19:00", "19:42"),
                          duration="42분", weather="맑음",
                          subjects=["오리", "벤치"], note="좋은 산책이었다")

    assert out.is_file()
    image = Image.open(out)
    assert image.size == (JOURNAL_W, JOURNAL_H)


def test_compose_journal_time_range_none_no_exception(tmp_path):
    """time_range를 모르면 예외 없이 그 줄만 생략한다."""
    scenes = make_journal_scenes(tmp_path, count=2)
    out = compose_journal(scenes, tmp_path / "no_time.png", time_range=None)
    assert out.is_file()


def test_compose_journal_without_panels_raises(tmp_path):
    metas = iter_frames(touch_frames(tmp_path / "f", REAL_NAMES[:1]))
    scenes = [KeyScene(record=FrameRecord(observation=observation(), meta=metas[0]))]
    with pytest.raises(IllustrateError, match="합성할 삽화가 없습니다"):
        compose_journal(scenes, tmp_path / "x.png")


def test_fit_no_upscale_does_not_enlarge_small_image():
    """카드 삽화는 원본보다 커지지 않는다 - 확대는 흐려진다."""
    small = Image.new("RGB", (40, 30), (10, 20, 30))
    fitted = _fit_no_upscale(small, 400, 300)

    assert fitted.size == (400, 300)     # 박스 자체는 항상 요청 크기(레터박스)
    off_x, off_y = (400 - 40) // 2, (300 - 30) // 2
    px = fitted.load()
    assert px[off_x, off_y] == (10, 20, 30)          # 원본 픽셀 그대로
    assert px[off_x - 1, off_y] == JOURNAL_BG        # 박스 나머지는 배경색(확대 안 됨)


def test_fit_no_upscale_shrinks_large_image():
    large = Image.new("RGB", (2000, 1000), (5, 5, 5))
    fitted = _fit_no_upscale(large, 400, 300)
    assert fitted.size == (400, 300)


# ============================================================ Stage 3 (감성 이미지 검증 루프)

def verdict(passed: bool, score: float, reasons=None, fix_hints="") -> dict:
    return {"pass": passed, "score": score,
            "reasons": reasons or [], "fix_hints": fix_hints}


def test_story_image_no_verify_generates_once(tmp_path):
    """verify=False(기본)면 이미지 API 호출은 1회이고 즉시 채택된다(현행 동작).

    verify_style=False: 이 테스트는 내용 검증 루프만 본다. 화풍 검사는
    build_story_image_style_check_* 테스트들이 별도로 다룬다.
    """
    records = make_records(tmp_path, 2)
    client = FakeClient(image_results=[_png_bytes()])

    out = build_story_image(client, records, "이야기", tmp_path / "out" / "story.png",
                            verify_style=False)

    image_calls = [c for c in client.calls if c["kind"] == "image"]
    json_calls = [c for c in client.calls if c["kind"] == "json"]
    assert len(image_calls) == 1
    assert len(json_calls) == 0
    assert out.is_file()
    assert list(out.parent.glob("story_image_candidate*.png")) == []


def test_story_image_verify_passes_first_try(tmp_path):
    """verify_style=False: 내용 검증 호출 수만 본다(화풍 검사는 별도 테스트)."""
    records = make_records(tmp_path, 2)
    png = _png_bytes(color=(10, 10, 10))
    client = FakeClient(image_results=[png], json_results=[verdict(True, 0.9)])

    out = build_story_image(client, records, "이야기",
                            tmp_path / "out" / "story.png", verify=True,
                            verify_style=False)

    image_calls = [c for c in client.calls if c["kind"] == "image"]
    json_calls = [c for c in client.calls if c["kind"] == "json"]
    assert len(image_calls) == 1
    assert len(json_calls) == 1
    assert out.read_bytes() == png
    assert list(out.parent.glob("story_image_candidate*.png")) == []


def test_story_image_verify_retries_with_latest_fix_hints(tmp_path):
    """1차 불합격 -> 2차 합격. fix_hints가 2차 프롬프트에 반영된다."""
    records = make_records(tmp_path, 2)
    png1 = _png_bytes(color=(10, 10, 10))
    png2 = _png_bytes(color=(200, 200, 200))
    client = FakeClient(
        image_results=[png1, png2],
        json_results=[
            verdict(False, 0.3, reasons=["실내인데 하늘이 보임"],
                    fix_hints="indoor scene, no sky"),
            verdict(True, 0.85),
        ],
    )

    out = build_story_image(client, records, "이야기",
                            tmp_path / "out" / "story.png", verify=True)

    image_calls = [c for c in client.calls if c["kind"] == "image"]
    assert len(image_calls) == 2
    assert image_calls[0]["kwargs"].get("tag") == "story_image"
    assert image_calls[1]["kwargs"].get("tag") == "story_image_retry1"
    assert "indoor scene, no sky" in image_calls[1]["spec"]
    assert out.read_bytes() == png2
    assert list(out.parent.glob("story_image_candidate*.png")) == []


def test_story_image_verify_all_fail_picks_best_score(tmp_path):
    """전부 불합격이면 이미지를 폐기하지 않고 score가 가장 높은 후보를 채택한다."""
    records = make_records(tmp_path, 2)
    png_a = _png_bytes(color=(1, 1, 1))
    png_b = _png_bytes(color=(2, 2, 2))
    png_c = _png_bytes(color=(3, 3, 3))
    client = FakeClient(
        image_results=[png_a, png_b, png_c],
        json_results=[verdict(False, 0.2), verdict(False, 0.5), verdict(False, 0.4)],
    )

    out = build_story_image(client, records, "이야기",
                            tmp_path / "out" / "story.png", verify=True)

    image_calls = [c for c in client.calls if c["kind"] == "image"]
    assert len(image_calls) == 3          # 1 + max_regens(2)
    assert out.read_bytes() == png_b       # score 0.5로 최고
    assert list(out.parent.glob("story_image_candidate*.png")) == []


def test_story_image_verify_call_fails_keeps_candidate(tmp_path):
    """검증 API 호출 자체가 실패(GMSError)하면 그 시점의 후보를 그대로 채택한다.

    검증은 품질 향상 장치이지 결과를 막는 차단 장치가 아니다.
    """
    records = make_records(tmp_path, 2)
    png = _png_bytes(color=(9, 9, 9))
    client = FakeClient(
        image_results=[png],
        errors=[None, None, GMSNetworkError("끊김")],
    )

    out = build_story_image(client, records, "이야기",
                            tmp_path / "out" / "story.png", verify=True)

    image_calls = [c for c in client.calls if c["kind"] == "image"]
    assert len(image_calls) == 1           # 검증 실패 시 재시도하지 않는다
    assert out.read_bytes() == png
    assert list(out.parent.glob("story_image_candidate*.png")) == []


# ============================================================ Stage 3 (감성 이미지 화풍 검사)

def test_build_story_image_style_check_fail_restyles_then_passes(tmp_path):
    """내용 합격 -> 화풍 1차 불합격 -> 2차(강조) 합격. 내용 검증은 다시 돌지 않는다
    (무한 왕복 방지). manifest에는 시도 2개가 남고 adopted_tag가 2차를 가리킨다."""
    records = make_records(tmp_path, 2)
    png_pass = _png_bytes(color=(10, 10, 10))
    png_restyled = _png_bytes(color=(20, 20, 20))
    client = FakeClient(
        image_results=[png_pass, png_restyled],
        json_results=[
            verdict(True, 0.9),                                      # 내용 검증: 합격
            {"is_photographic": True, "matches_style": False},       # 1차 화풍 검사: 불합격
            {"is_photographic": False, "matches_style": True},       # 2차 화풍 검사: 합격
        ],
    )

    out = build_story_image(client, records, "이야기",
                            tmp_path / "out" / "story.png", verify=True)

    image_calls = [c for c in client.calls if c["kind"] == "image"]
    json_calls = [c for c in client.calls if c["kind"] == "json"]
    assert len(image_calls) == 2          # 원본 + 2차(강조) 재생성
    assert len(json_calls) == 3           # 내용검증 1회 + 화풍검사 2회 (내용 재검증 없음)
    assert image_calls[1]["kwargs"].get("tag") == "story_image_restyle"
    assert P.STYLE_EMPHASIS in image_calls[1]["spec"]
    assert out.read_bytes() == png_restyled

    manifest = json.loads(
        (tmp_path / "out" / "image_manifest.json").read_text(encoding="utf-8"))
    assert len(manifest) == 1
    assert manifest[0]["adopted_tag"] == "story_image_restyle"
    attempts = manifest[0]["attempts"]
    assert len(attempts) == 2
    assert attempts[0]["tag"] == "story_image"
    assert attempts[0]["content_check"]["pass"] is True
    assert attempts[0]["style_check"] == {"is_photographic": True, "matches_style": False}
    assert attempts[1]["tag"] == "story_image_restyle"
    assert attempts[1]["style_check"] == {"is_photographic": False, "matches_style": True}


def test_build_story_image_photoreal_skips_style_check(tmp_path):
    records = make_records(tmp_path, 2)
    client = FakeClient(image_results=[_png_bytes()])

    build_story_image(client, records, "이야기", tmp_path / "out" / "story.png",
                      style="photoreal")

    assert not [c for c in client.calls if c["kind"] == "json"]


# ============================================================ image_manifest.json 기록

def test_log_image_generation_creates_new_file(tmp_path):
    _log_image_generation(tmp_path, {"output": "a.png", "tag": "panel_1"})
    saved = json.loads((tmp_path / config.IMAGE_MANIFEST_NAME).read_text(encoding="utf-8"))
    assert saved == [{"output": "a.png", "tag": "panel_1"}]


def test_log_image_generation_appends(tmp_path):
    _log_image_generation(tmp_path, {"output": "a.png"})
    _log_image_generation(tmp_path, {"output": "b.png"})
    saved = json.loads((tmp_path / config.IMAGE_MANIFEST_NAME).read_text(encoding="utf-8"))
    assert [e["output"] for e in saved] == ["a.png", "b.png"]


def test_log_image_generation_recovers_from_broken_json(tmp_path, capsys):
    manifest = tmp_path / config.IMAGE_MANIFEST_NAME
    manifest.write_text("{not json", encoding="utf-8")

    _log_image_generation(tmp_path, {"output": "a.png"})

    saved = json.loads(manifest.read_text(encoding="utf-8"))
    assert saved == [{"output": "a.png"}]
    assert "손상되어 새로 시작합니다" in capsys.readouterr().err


# ============================================================ Stage 3 (저널 조립)

def make_journal_records(tmp_path, count=5):
    metas = iter_frames(touch_frames(tmp_path / "f", REAL_NAMES[:count]))
    return [FrameRecord(observation=observation(location_type=f"loc{i}"), meta=m)
            for i, m in enumerate(metas)]


def test_build_journal_end_to_end(tmp_path):
    records = make_journal_records(tmp_path, 5)
    client = FakeClient()

    out = build_journal(client, records, tmp_path / "out" / "journal.png",
                        event_count=4)

    image_calls = [c for c in client.calls if c["kind"] == "image"]
    assert len(image_calls) == 4
    assert out.is_file()
    assert Image.open(out).size == (JOURNAL_W, JOURNAL_H)


def test_build_journal_caption_failure_falls_back(tmp_path, capsys):
    """캡션 생성이 실패해도 이미 만든(과금된) 삽화를 버리지 않고 대체값을 쓴다."""
    records = make_journal_records(tmp_path, 5)
    # 첫 이벤트: 프롬프트 작성(성공) -> 이미지 생성(성공) -> 캡션 작성(실패)
    # verify_style=False: 화풍 검사 호출이 끼어들어 에러 소비 순서가 흔들리는
    # 것을 막는다 - 이 테스트는 캡션 실패 폴백만 본다.
    client = FakeClient(errors=[None, None, GMSNetworkError("끊김")])

    out = build_journal(client, records, tmp_path / "out" / "journal.png",
                        event_count=4, verify_style=False)

    assert out.is_file()
    err = capsys.readouterr().err
    assert "캡션 생성 실패" in err and "로 대체합니다" in err


def test_build_journal_writes_panel_dir(tmp_path):
    records = make_journal_records(tmp_path, 4)
    client = FakeClient()
    panel_dir = tmp_path / "panels"

    build_journal(client, records, tmp_path / "out" / "journal.png",
                  event_count=4, panel_dir=panel_dir)

    saved = sorted(p.name for p in panel_dir.iterdir())
    assert saved == ["event_01.png", "event_02.png", "event_03.png", "event_04.png"]


def test_build_journal_partial_failure_still_produces_journal(tmp_path, capsys):
    """이벤트 하나의 삽화 생성이 실패해도 나머지로 저널을 완성한다.

    한 번의 API 실패(429/네트워크 끊김 등)로 이미 성공한 나머지 삽화까지
    통째로 버리면 손해가 더 크다 - observe_frames와 같은 원칙.
    """
    records = make_journal_records(tmp_path, 5)
    # 이벤트마다 프롬프트(text) -> 이미지(image) -> 캡션(text) 순으로 호출된다.
    # 1번째 이벤트는 전부 성공, 2번째 이벤트의 프롬프트 작성에서 실패시킨다.
    # verify_style=False: 화풍 검사 호출이 끼어들면 이 순서가 흔들린다.
    client = FakeClient(errors=[None, None, None, GMSNetworkError("끊김")])

    out = build_journal(client, records, tmp_path / "out" / "journal.png",
                        event_count=3, verify_style=False)

    assert out.is_file()
    image_calls = [c for c in client.calls if c["kind"] == "image"]
    assert len(image_calls) == 2   # 실패한 이벤트는 이미지 호출까지 가지 않는다
    err = capsys.readouterr().err
    assert "삽화 생성 실패" in err
    assert "저널은 성공한 2개로 만듭니다" in err


def test_build_journal_all_events_fail_raises(tmp_path):
    records = make_journal_records(tmp_path, 3)
    client = FakeClient(errors=[GMSNetworkError("끊김")] * 3)

    with pytest.raises(IllustrateError, match="전부 삽화 생성에 실패"):
        build_journal(client, records, tmp_path / "out" / "journal.png",
                      event_count=3)


# ============================================================ Stage 3 (패널 전용, 보드 없음)

def test_build_panels_creates_expected_files_no_caption(tmp_path):
    """이벤트 4개 -> 이미지 4회(화풍 검사 자동 합격이라 재시도 없음) + 캡션 호출 0회
    + panel_dir에 event_01~04.png 4개(+manifest). 보드(walk_journal.png)는 만들지 않는다."""
    records = make_journal_records(tmp_path, 4)
    client = FakeClient()
    panel_dir = tmp_path / "out"

    result = build_panels(client, records, panel_dir, event_count=4)

    assert result == panel_dir
    saved = sorted(p.name for p in panel_dir.glob("event_*.png"))
    assert saved == ["event_01.png", "event_02.png", "event_03.png", "event_04.png"]
    assert (panel_dir / config.IMAGE_MANIFEST_NAME).is_file()
    assert not (tmp_path / "out" / config.JOURNAL_NAME).exists()

    image_calls = [c for c in client.calls if c["kind"] == "image"]
    assert len(image_calls) == 4
    assert not any(c["spec"] is P.PANEL_CAPTION_WRITER for c in client.calls)


def test_build_panels_default_no_reference(tmp_path):
    """use_reference=False(기본)면 참조 없이 생성되고 재해석 지시도 없다."""
    records = make_journal_records(tmp_path, 4)
    client = FakeClient()

    build_panels(client, records, tmp_path / "panels", event_count=2)

    image_calls = [c for c in client.calls if c["kind"] == "image"]
    assert image_calls and all(c["kwargs"].get("reference") is None for c in image_calls)
    assert not any(_REPAINT in c["spec"] for c in image_calls)


def test_build_panels_use_reference_true_passes_reference(tmp_path):
    """use_reference=True면 실제 참조 파일이 있는 이벤트에 재해석 지시가 붙는다."""
    records = make_journal_records(tmp_path, 4)
    client = FakeClient()

    build_panels(client, records, tmp_path / "panels", event_count=2, use_reference=True)

    image_calls = [c for c in client.calls if c["kind"] == "image"]
    assert image_calls and any(_REPAINT in c["spec"] for c in image_calls)


def test_build_panels_all_events_fail_raises(tmp_path):
    records = make_journal_records(tmp_path, 3)
    client = FakeClient(errors=[GMSNetworkError("끊김")] * 3)

    with pytest.raises(IllustrateError, match="전부 삽화 생성에 실패"):
        build_panels(client, records, tmp_path / "panels", event_count=3)


def test_build_panels_partial_failure_still_returns_dir(tmp_path, capsys):
    """이벤트 하나의 삽화 생성이 실패해도 나머지 패널로 계속 진행한다."""
    records = make_journal_records(tmp_path, 3)
    # 1번째 이벤트: 프롬프트(text) 성공 -> 2번째 이벤트의 프롬프트 작성에서 실패.
    client = FakeClient(errors=[None, None, GMSNetworkError("끊김")])

    result = build_panels(client, records, tmp_path / "panels", event_count=3,
                          verify_style=False)

    assert result.is_dir()
    saved = sorted(p.name for p in result.glob("event_*.png"))
    assert len(saved) == 2
    assert "삽화 생성 실패" in capsys.readouterr().err


# ============================================================ Stage 3 (저널 패널 화풍 검사-재생성)

def style_verdict(*, is_photographic: bool, matches_style: bool = True,
                  face_visible: bool = False) -> dict:
    return {"is_photographic": is_photographic, "matches_style": matches_style,
            "face_visible": face_visible}


def test_build_journal_style_check_pass_generates_once_per_panel(tmp_path):
    """검사 합격이면 패널마다 이미지 호출은 1회로 끝난다."""
    records = make_journal_records(tmp_path, 4)
    client = FakeClient(json_results=[
        style_verdict(is_photographic=False, matches_style=True),
        style_verdict(is_photographic=False, matches_style=True),
    ])
    panel_dir = tmp_path / "panels"

    build_journal(client, records, tmp_path / "out" / "journal.png",
                  event_count=2, panel_dir=panel_dir)

    image_calls = [c for c in client.calls if c["kind"] == "image"]
    json_calls = [c for c in client.calls if c["kind"] == "json"]
    assert len(image_calls) == 2
    assert len(json_calls) == 2
    assert all(c["kwargs"].get("tag", "").startswith("style_check_") for c in json_calls)
    # 임시 검사 파일이 정리되어 최종 패널만 남는다.
    assert sorted(p.name for p in panel_dir.iterdir()) == ["event_01.png", "event_02.png"]


def test_build_journal_style_check_fail_regenerates_once(tmp_path):
    """is_photographic=True(불합격)면 그 패널만 이미지가 2회(원본+재생성) 나간다."""
    records = make_journal_records(tmp_path, 4)
    client = FakeClient(json_results=[
        style_verdict(is_photographic=True, matches_style=False),   # 1번: 불합격
        style_verdict(is_photographic=False, matches_style=True),   # 2번: 합격
    ])

    build_journal(client, records, tmp_path / "out" / "journal.png", event_count=2)

    image_calls = [c for c in client.calls if c["kind"] == "image"]
    assert len(image_calls) == 3   # 1번 패널만 원본+재생성
    restyle_calls = [c for c in image_calls if c["kwargs"].get("tag") == "panel_1_restyle"]
    assert len(restyle_calls) == 1
    assert "STRICTLY" in restyle_calls[0]["spec"]


def test_build_journal_style_check_error_keeps_original_panel(tmp_path, capsys):
    """검사 호출 자체가 GMSError면 원본 패널을 그대로 채택하고 경고만 남긴다."""
    records = make_journal_records(tmp_path, 2)
    # 순서: 프롬프트(text, 성공) -> 이미지(image, 성공) -> 화풍검사(json, 실패)
    client = FakeClient(errors=[None, None, GMSNetworkError("끊김")])

    out = build_journal(client, records, tmp_path / "out" / "journal.png", event_count=1)

    image_calls = [c for c in client.calls if c["kind"] == "image"]
    assert len(image_calls) == 1   # 재생성 없음, 원본 그대로 채택
    assert out.is_file()
    err = capsys.readouterr().err
    assert "검사 실패" in err and "채택합니다" in err


def test_build_journal_photoreal_style_skips_style_check(tmp_path):
    """photoreal 스타일은 사진풍이 목적이므로 화풍 검사 자체를 하지 않는다."""
    records = make_journal_records(tmp_path, 2)
    client = FakeClient()

    build_journal(client, records, tmp_path / "out" / "journal.png",
                  event_count=2, style="photoreal")

    assert not [c for c in client.calls if c["kind"] == "json"]


def test_build_journal_verify_style_false_skips_style_check(tmp_path):
    """verify_style=False면 화풍 검사 호출 자체가 없다."""
    records = make_journal_records(tmp_path, 2)
    client = FakeClient()

    build_journal(client, records, tmp_path / "out" / "journal.png",
                  event_count=2, verify_style=False)

    assert not [c for c in client.calls if c["kind"] == "json"]


# ============================================================ 화풍 검증 사다리
# (_render_with_style_enforcement 직접 검증 - GMSClient 스텁만 사용)

def test_render_with_style_enforcement_first_stage_pass(tmp_path):
    """1차 검사 합격이면 이미지 1회 + 검사 1회로 끝난다."""
    reference = tmp_path / "ref.jpg"
    png1 = _png_bytes()
    client = FakeClient(
        image_results=[png1],
        json_results=[style_verdict(is_photographic=False, matches_style=True)],
    )

    image, prompt, attempts = _render_with_style_enforcement(
        client, "a quiet path", style="watercolor", reference=reference,
        tag_base="panel_1",
    )

    image_calls = [c for c in client.calls if c["kind"] == "image"]
    json_calls = [c for c in client.calls if c["kind"] == "json"]
    assert len(image_calls) == 1
    assert len(json_calls) == 1
    assert image == png1
    assert len(attempts) == 1
    assert attempts[0]["tag"] == "panel_1"
    assert attempts[0]["with_reference"] is True
    assert attempts[0]["style_check"]["matches_style"] is True


def test_render_with_style_enforcement_escalates_to_second_stage(tmp_path):
    """1차 불합격 -> 2차(강조, 참조 유지) 합격.

    2차 호출에도 reference가 그대로 전달되고 STYLE_EMPHASIS가 붙되,
    스타일 전문(Art style 블록의 설명)이 두 번 등장하지는 않는다.
    """
    reference = tmp_path / "ref.jpg"
    png2 = _png_bytes(color=(2, 2, 2))
    client = FakeClient(
        image_results=[_png_bytes(color=(1, 1, 1)), png2],
        json_results=[
            style_verdict(is_photographic=True, matches_style=False),
            style_verdict(is_photographic=False, matches_style=True),
        ],
    )

    image, prompt, attempts = _render_with_style_enforcement(
        client, "a quiet path", style="watercolor", reference=reference,
        tag_base="panel_1",
    )

    image_calls = [c for c in client.calls if c["kind"] == "image"]
    assert len(image_calls) == 2
    second_call = image_calls[1]
    assert second_call["kwargs"].get("tag") == "panel_1_restyle"
    assert second_call["kwargs"].get("reference") == reference   # 참조 유지
    assert P.STYLE_EMPHASIS in second_call["spec"]
    style_text = P.IMAGE_STYLES["watercolor"]
    assert second_call["spec"].count(style_text) == 1            # 이중 등장 없음
    assert image == png2
    assert len(attempts) == 2
    assert attempts[1]["tag"] == "panel_1_restyle"
    assert attempts[1]["with_reference"] is True
    assert attempts[1]["style_check"]["matches_style"] is True


def test_render_with_style_enforcement_escalates_to_third_stage_drops_reference(tmp_path):
    """2차도 불합격 -> 3차(참조 제거). reference=None으로 호출되고
    _REFERENCE_RULE 문구("Completely repaint it")가 프롬프트에 없다."""
    reference = tmp_path / "ref.jpg"
    png3 = _png_bytes(color=(3, 3, 3))
    client = FakeClient(
        image_results=[_png_bytes(color=(1, 1, 1)), _png_bytes(color=(2, 2, 2)), png3],
        json_results=[
            style_verdict(is_photographic=True, matches_style=False),
            style_verdict(is_photographic=True, matches_style=False),
            style_verdict(is_photographic=False, matches_style=True),
        ],
    )

    image, prompt, attempts = _render_with_style_enforcement(
        client, "a quiet path", style="watercolor", reference=reference,
        tag_base="panel_1",
    )

    image_calls = [c for c in client.calls if c["kind"] == "image"]
    assert len(image_calls) == 3
    third_call = image_calls[2]
    assert third_call["kwargs"].get("tag") == "panel_1_noref"
    assert third_call["kwargs"].get("reference") is None
    assert "Completely repaint it" not in third_call["spec"]
    assert prompt == third_call["spec"]
    assert image == png3
    assert len(attempts) == 3
    assert attempts[2]["tag"] == "panel_1_noref"
    assert attempts[2]["with_reference"] is False


def test_render_with_style_enforcement_third_stage_fail_adopts_with_warning(tmp_path, capsys):
    """3차도 불합격이면 더 이상 재시도하지 않고 경고와 함께 3차본을 채택한다."""
    reference = tmp_path / "ref.jpg"
    png3 = _png_bytes(color=(3, 3, 3))
    client = FakeClient(
        image_results=[_png_bytes(color=(1, 1, 1)), _png_bytes(color=(2, 2, 2)), png3],
        json_results=[
            style_verdict(is_photographic=True, matches_style=False),
            style_verdict(is_photographic=True, matches_style=False),
            style_verdict(is_photographic=True, matches_style=False),
        ],
    )

    image, prompt, attempts = _render_with_style_enforcement(
        client, "a quiet path", style="watercolor", reference=reference,
        tag_base="panel_1",
    )

    image_calls = [c for c in client.calls if c["kind"] == "image"]
    assert len(image_calls) == 3   # 비용 상한 준수 (더 이상 늘지 않는다)
    assert image == png3
    assert len(attempts) == 3
    assert all(a["style_check"] is not None for a in attempts)
    err = capsys.readouterr().err
    assert "panel_1_noref" in err and "채택합니다" in err


def test_render_with_style_enforcement_check_error_adopts_immediately(tmp_path):
    """검사 호출 자체가 GMSError면 재시도 없이 그 후보를 즉시 채택한다."""
    reference = tmp_path / "ref.jpg"
    png1 = _png_bytes()
    client = FakeClient(
        image_results=[png1],
        errors=[None, GMSNetworkError("끊김")],   # 이미지 생성은 성공, 검사가 실패
    )

    image, prompt, attempts = _render_with_style_enforcement(
        client, "a quiet path", style="watercolor", reference=reference,
        tag_base="panel_1",
    )

    image_calls = [c for c in client.calls if c["kind"] == "image"]
    json_calls = [c for c in client.calls if c["kind"] == "json"]
    assert len(image_calls) == 1
    assert len(json_calls) == 1
    assert image == png1
    assert len(attempts) == 1
    assert attempts[0]["style_check"] is None


def test_render_with_style_enforcement_skips_check_for_photoreal(tmp_path):
    reference = tmp_path / "ref.jpg"
    client = FakeClient(image_results=[_png_bytes()])

    _, _, attempts = _render_with_style_enforcement(
        client, "a quiet path", style="photoreal", reference=reference,
        tag_base="panel_1",
    )

    assert not [c for c in client.calls if c["kind"] == "json"]
    assert len(client.calls) == 1   # 이미지 1회뿐
    assert len(attempts) == 1
    assert attempts[0]["style_check"] is None


def test_render_with_style_enforcement_skips_check_when_verify_style_false(tmp_path):
    reference = tmp_path / "ref.jpg"
    client = FakeClient(image_results=[_png_bytes()])

    _, _, attempts = _render_with_style_enforcement(
        client, "a quiet path", style="watercolor", reference=reference,
        tag_base="panel_1", verify_style=False,
    )

    assert not [c for c in client.calls if c["kind"] == "json"]
    assert len(client.calls) == 1
    assert len(attempts) == 1


def test_render_with_style_enforcement_no_reference_from_start_stays_without_reference(tmp_path):
    """reference=None으로 호출되면(panels 기본값) 1~3차 전부 참조 없이 조립된다.

    with_reference = (reference is not None)이 1차부터 이미 False로 평가되므로
    _REFERENCE_RULE("Completely repaint it")이 세 단계 어디에도 없다. 3차는
    "참조를 새로 제거"하는 단계가 아니라 2차와 같은 조건(참조 없음 +
    STYLE_EMPHASIS)으로 한 번 더 생성하는 것과 동치다.
    """
    client = FakeClient(
        image_results=[_png_bytes(color=(1, 1, 1)), _png_bytes(color=(2, 2, 2)),
                       _png_bytes(color=(3, 3, 3))],
        json_results=[
            style_verdict(is_photographic=True, matches_style=False),
            style_verdict(is_photographic=True, matches_style=False),
            style_verdict(is_photographic=False, matches_style=True),
        ],
    )

    image, prompt, attempts = _render_with_style_enforcement(
        client, "a quiet path", style="watercolor", reference=None,
        tag_base="panel_1",
    )

    image_calls = [c for c in client.calls if c["kind"] == "image"]
    assert len(image_calls) == 3
    assert all(c["kwargs"].get("reference") is None for c in image_calls)
    assert not any(_REPAINT in c["spec"] for c in image_calls)
    assert P.STYLE_EMPHASIS in image_calls[1]["spec"]
    assert P.STYLE_EMPHASIS in image_calls[2]["spec"]
    assert len(attempts) == 3
    assert all(a["with_reference"] is False for a in attempts)


def test_render_with_style_enforcement_uses_initial_without_regenerating(tmp_path):
    """initial을 주면 1차 생성을 건너뛰고 그것을 1차 후보로 취급한다."""
    reference = tmp_path / "ref.jpg"
    initial_bytes = _png_bytes(color=(9, 9, 9))
    client = FakeClient(
        json_results=[style_verdict(is_photographic=False, matches_style=True)],
    )

    image, prompt, attempts = _render_with_style_enforcement(
        client, "a quiet path", style="watercolor", reference=reference,
        tag_base="story_image", initial=initial_bytes,
    )

    assert not [c for c in client.calls if c["kind"] == "image"]   # 재생성 없음
    assert image == initial_bytes
    assert len(attempts) == 1


# ============================================================ 화풍 검증 사다리 (build_journal 통합)

def test_build_journal_manifest_adopted_tag_matches_final_stage(tmp_path):
    """2차까지 승급했을 때 manifest의 adopted_tag/tag/final_prompt가
    실제로 채택된 시도와 일치한다."""
    records = make_journal_records(tmp_path, 1)
    client = FakeClient(json_results=[
        style_verdict(is_photographic=True, matches_style=False),   # 1차 불합격
        style_verdict(is_photographic=False, matches_style=True),   # 2차 합격
    ])

    build_journal(client, records, tmp_path / "out" / "journal.png", event_count=1)

    manifest = json.loads(
        (tmp_path / "out" / "image_manifest.json").read_text(encoding="utf-8"))
    assert len(manifest) == 1
    entry = manifest[0]
    assert entry["adopted_tag"] == "panel_1_restyle"
    assert entry["tag"] == "panel_1_restyle"
    assert P.STYLE_EMPHASIS in entry["final_prompt"]
    assert len(entry["attempts"]) == 2


def test_panel_style_checker_and_story_verifier_token_limits_increased():
    """검증 호출이 사다리의 관문이라 잘리면 생성 비용이 통째로 낭비된다."""
    assert P.PANEL_STYLE_CHECKER.max_output_tokens == 8192
    assert P.STORY_IMAGE_VERIFIER.max_output_tokens == 8192


# ============================================================ 화풍 검사 기준 강화 (face_visible)

def test_style_check_passes_requires_all_three_conditions():
    """혼종(matches_style=False)이나 얼굴 노출(face_visible=True)만으로도 불합격이다."""
    clean = {"is_photographic": False, "matches_style": True, "face_visible": False}
    assert _style_check_passes(clean)

    face_only = {"is_photographic": False, "matches_style": True, "face_visible": True}
    assert not _style_check_passes(face_only)

    photo_only = {"is_photographic": True, "matches_style": True, "face_visible": False}
    assert not _style_check_passes(photo_only)

    hybrid_only = {"is_photographic": False, "matches_style": False, "face_visible": False}
    assert not _style_check_passes(hybrid_only)


def test_render_with_style_enforcement_escalates_on_face_visible_alone():
    """다른 조건은 정상이어도 face_visible=true 단독으로 다음 단계로 승급한다."""
    reference = Path("ref.jpg")
    client = FakeClient(
        image_results=[_png_bytes(color=(1, 1, 1)), _png_bytes(color=(2, 2, 2))],
        json_results=[
            style_verdict(is_photographic=False, matches_style=True, face_visible=True),
            style_verdict(is_photographic=False, matches_style=True, face_visible=False),
        ],
    )

    image, prompt, attempts = _render_with_style_enforcement(
        client, "a quiet path", style="watercolor", reference=reference,
        tag_base="panel_1",
    )

    image_calls = [c for c in client.calls if c["kind"] == "image"]
    assert len(image_calls) == 2
    assert attempts[0]["style_check"]["face_visible"] is True
    assert attempts[1]["style_check"]["face_visible"] is False


# ============================================================ 여백 결정적 제거 (_trim_margins)

def _margin_png_bytes(size=(200, 160), border=15,
                      border_color=(255, 255, 255), inner_color=(90, 140, 90)):
    """사방에 균일한 종이 여백이 있는 PNG."""
    image = Image.new("RGB", size, border_color)
    inner = Image.new("RGB", (size[0] - 2 * border, size[1] - 2 * border), inner_color)
    image.paste(inner, (border, border))
    buffer = io.BytesIO()
    image.save(buffer, "PNG")
    return buffer.getvalue()


def _boxed_content_png_bytes(size=(200, 200), background=(245, 245, 250), content=(40, 90, 60)):
    """배경이 화면 대부분(60%)을 차지하고 중앙 40%만 내용인 PNG.

    밝은 하늘이 화면 대부분을 채우는 상황을 흉내낸다 - 트림 함수 입장에서는
    "균일한 여백에 둘러싸인 작은 내용"과 구조적으로 동일하므로, 안전장치가
    없으면 그림 내용의 대부분을 잘라내는 사고가 난다.
    """
    image = Image.new("RGB", size, background)
    cw, ch = int(size[0] * 0.4), int(size[1] * 0.4)
    ox, oy = (size[0] - cw) // 2, (size[1] - ch) // 2
    image.paste(Image.new("RGB", (cw, ch), content), (ox, oy))
    buffer = io.BytesIO()
    image.save(buffer, "PNG")
    return buffer.getvalue()


def test_trim_margins_removes_uniform_border():
    data = _margin_png_bytes(size=(200, 160), border=15)
    trimmed = _trim_margins(data)
    image = Image.open(io.BytesIO(trimmed))
    assert image.size == (170, 130)


def test_trim_margins_leaves_borderless_image_unchanged():
    data = _png_bytes(size=(120, 90))
    trimmed = _trim_margins(data)
    assert trimmed == data
    assert Image.open(io.BytesIO(trimmed)).size == (120, 90)


def test_trim_margins_safety_guard_keeps_original_on_excessive_crop():
    """밝은 하늘(넓은 배경) 때문에 과도하게 잘리려 하면 안전장치가 원본을 지킨다."""
    data = _boxed_content_png_bytes(size=(200, 200))
    trimmed = _trim_margins(data)
    assert trimmed == data
    assert Image.open(io.BytesIO(trimmed)).size == (200, 200)


def test_render_with_style_enforcement_trims_adopted_image():
    """채택 확정 직후 트림이 적용되고 attempts에 trimmed 여부가 남는다."""
    reference = Path("ref.jpg")
    bordered = _margin_png_bytes(size=(200, 160), border=15)
    client = FakeClient(
        image_results=[bordered],
        json_results=[style_verdict(is_photographic=False, matches_style=True)],
    )

    image, prompt, attempts = _render_with_style_enforcement(
        client, "a quiet path", style="watercolor", reference=reference,
        tag_base="panel_1",
    )

    assert Image.open(io.BytesIO(image)).size == (170, 130)
    assert attempts[0]["trimmed"] is True


def test_render_with_style_enforcement_no_trim_when_no_margin():
    reference = Path("ref.jpg")
    clean = _png_bytes(size=(120, 90))
    client = FakeClient(
        image_results=[clean],
        json_results=[style_verdict(is_photographic=False, matches_style=True)],
    )

    image, prompt, attempts = _render_with_style_enforcement(
        client, "a quiet path", style="watercolor", reference=reference,
        tag_base="panel_1",
    )

    assert image == clean
    assert attempts[0]["trimmed"] is False


def test_build_journal_manifest_records_trimmed_flag(tmp_path):
    records = make_journal_records(tmp_path, 1)
    bordered = _margin_png_bytes(size=(200, 160), border=15)
    client = FakeClient(
        image_results=[bordered],
        json_results=[style_verdict(is_photographic=False, matches_style=True)],
    )

    build_journal(client, records, tmp_path / "out" / "journal.png", event_count=1)

    manifest = json.loads(
        (tmp_path / "out" / "image_manifest.json").read_text(encoding="utf-8"))
    assert manifest[0]["trimmed"] is True