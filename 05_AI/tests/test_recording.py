"""records.py 검증.

무게중심은 세 가지다.
  1. 실제 프레임 파일명(f_0000128_t000m08.53s.jpg)을 정확히 해석하는가
  2. 파싱 실패가 조용히 넘어가지 않는가
  3. 분할 전 frame_records.json을 계속 읽을 수 있는가
"""

from __future__ import annotations

import json
import random
from pathlib import Path

import pytest

from walklog.records import (
    UNKNOWN,
    FrameMeta,
    FrameRecord,
    ManifestError,
    RecordsError,
    WalkInfo,
    dump_records,
    format_elapsed,
    iter_frames,
    load_manifest,
    load_records,
    parse_frame_name,
    sample_time_quantiles,
    to_json_lines,
    usable,
    walk_duration,
)

# data/sample_image 의 실제 파일명들
REAL_NAMES = [
    "f_0000128_t000m08.53s.jpg",
    "f_0000160_t000m10.67s.jpg",
    "f_0000960_t001m04.00s.jpg",
    "f_0001347_t001m29.80s.jpg",
    "f_0001605_t001m47.00s.jpg",
]


def touch_frames(directory, names=REAL_NAMES):
    directory.mkdir(parents=True, exist_ok=True)
    for name in names:
        (directory / name).write_bytes(b"\xff\xd8\xff")
    return directory


# ------------------------------------------------------------ 파일명 규약

@pytest.mark.parametrize("name,index,offset", [
    ("f_0000128_t000m08.53s.jpg", 128, 8.53),
    ("f_0000960_t001m04.00s.jpg", 960, 64.0),
    ("f_0001605_t001m47.00s.jpg", 1605, 107.0),
    ("f_0001351_t001m30.07s.jpg", 1351, 90.07),
])
def test_parse_real_frame_names(name, index, offset):
    assert parse_frame_name(name) == (index, pytest.approx(offset))


@pytest.mark.parametrize("name", ["frame_001.jpg", "IMG_1234.jpg", "f_abc_t0m0s.jpg", ""])
def test_parse_rejects_other_names(name):
    assert parse_frame_name(name) is None


@pytest.mark.parametrize("seconds,text", [
    (None, UNKNOWN), (0.0, "0분 0초"), (8.53, "0분 9초"),
    (64.0, "1분 4초"), (107.0, "1분 47초"),
])
def test_format_elapsed(seconds, text):
    assert format_elapsed(seconds) == text


# ------------------------------------------------------------ 탐색

def test_flat_layout(tmp_path):
    """data/sample_image 처럼 평면 배치인 경우."""
    metas = iter_frames(touch_frames(tmp_path / "sample_image"))

    assert [m.name for m in metas] == REAL_NAMES          # 시간순
    assert metas[0].offset_seconds == pytest.approx(8.53)
    assert metas[-1].offset_seconds == pytest.approx(107.0)
    # 평면 배치에는 세그먼트 개념이 없다.
    # 분할 전에는 폴더명("sample_image")이 프롬프트에 들어갔다.
    assert all(m.segment == UNKNOWN for m in metas)


def test_segment_layout(tmp_path):
    """seg_XXXX 하위 배치인 경우. 분할 전 docstring이 가정한 구조."""
    root = tmp_path / "frames"
    touch_frames(root / "seg_0000", REAL_NAMES[:2])
    touch_frames(root / "seg_0001", REAL_NAMES[2:])

    metas = iter_frames(root)
    assert [m.segment for m in metas] == ["seg_0000", "seg_0000",
                                         "seg_0001", "seg_0001", "seg_0001"]
    assert [m.name for m in metas] == REAL_NAMES


def test_sorted_by_time_not_filename(tmp_path):
    """파일명 정렬과 시간순이 다를 때 시간순을 따르는지."""
    names = ["f_0000960_t001m04.00s.jpg", "f_0000128_t000m08.53s.jpg"]
    metas = iter_frames(touch_frames(tmp_path / "f", names))
    assert [m.name for m in metas] == list(reversed(names))


def test_unparsable_name_warns_and_sorts_last(tmp_path, capsys):
    """파싱 실패가 조용히 넘어가지 않아야 한다.

    분할 전에는 _sort=0.0으로 떨어져 맨 앞에 왔다. 그러면 일지의 첫 문단이
    엉뚱한 장면으로 시작하는데, 결과물은 그럴듯해서 알아챌 수 없다.
    """
    metas = iter_frames(touch_frames(
        tmp_path / "f", REAL_NAMES[:2] + ["IMG_9999.jpg"]))

    assert metas[-1].name == "IMG_9999.jpg"
    assert metas[-1].offset_seconds is None
    assert metas[-1].elapsed == UNKNOWN

    err = capsys.readouterr().err
    assert "촬영 시각을 읽지 못한" in err and "IMG_9999.jpg" in err


def test_png_and_jpeg_both_found(tmp_path):
    directory = touch_frames(tmp_path / "f", REAL_NAMES[:1])
    (directory / "f_0000200_t000m13.00s.png").write_bytes(b"\x89PNG")
    assert len(iter_frames(directory)) == 2


def test_missing_dir_and_empty_dir(tmp_path):
    with pytest.raises(RecordsError, match="프레임 폴더가 없습니다"):
        iter_frames(tmp_path / "nope")

    empty = tmp_path / "empty"
    empty.mkdir()
    with pytest.raises(RecordsError, match="찾지 못했습니다"):
        iter_frames(empty)


# ------------------------------------------------------------ 표본 추출

def make_metas(count: int) -> list[FrameMeta]:
    """오프셋만 0, 1, 2, ...초로 증가하는 더미 메타. 파일은 필요 없다."""
    return [
        FrameMeta(path=Path(f"f_{i:04d}.jpg"), index=i, offset_seconds=float(i))
        for i in range(count)
    ]


def make_timed_metas(offsets) -> list[FrameMeta]:
    """지정한 경과 초 목록으로 더미 메타를 만든다. 시간 불균등 분포를 흉내낼 때 쓴다."""
    return [
        FrameMeta(path=Path(f"f_{i:04d}.jpg"), index=i, offset_seconds=float(o))
        for i, o in enumerate(offsets)
    ]


def test_sample_time_quantiles_deterministic_with_seed():
    metas = make_metas(20)
    first = sample_time_quantiles(metas, 4, rng=random.Random(42))
    second = sample_time_quantiles(metas, 4, rng=random.Random(42))
    assert [m.name for m in first] == [m.name for m in second]


def test_sample_time_quantiles_no_shrink_when_not_enough_frames():
    """뽑을 등분 수보다 프레임이 적으면 전부 그대로 돌려준다."""
    metas = make_metas(3)
    assert sample_time_quantiles(metas, 4, rng=random.Random(0)) == metas


def test_sample_time_quantiles_exact_n_returns_all():
    metas = make_metas(4)
    assert sample_time_quantiles(metas, 4, rng=random.Random(0)) == metas


def test_sample_time_quantiles_rejects_non_positive_n():
    with pytest.raises(ValueError, match="1 이상"):
        sample_time_quantiles(make_metas(5), 0)


def test_sample_time_quantiles_rejects_bad_band_ratio():
    with pytest.raises(ValueError, match="band_ratio"):
        sample_time_quantiles(make_metas(5), 2, band_ratio=0.0)
    with pytest.raises(ValueError, match="band_ratio"):
        sample_time_quantiles(make_metas(5), 2, band_ratio=1.5)


def test_sample_time_quantiles_minimum_gap_guaranteed():
    """band_ratio=0.5, n=4, 240초 산책이면 인접 표본 간 최소 30초 간격이 보장된다.

    (1 - band_ratio) * span / n = 0.5 * 240 / 4 = 30초.
    시드를 여러 개 돌려 우연히 통과하는 게 아님을 확인한다.
    """
    offsets = [i * 240 / 39 for i in range(40)]   # 0~240초에 균등 분포
    metas = make_timed_metas(offsets)

    for seed in range(20):
        picks = sample_time_quantiles(metas, 4, rng=random.Random(seed))
        assert len(picks) == 4
        vals = sorted(p.offset_seconds for p in picks)
        gaps = [b - a for a, b in zip(vals, vals[1:])]
        assert all(gap >= 30 - 1e-9 for gap in gaps), (seed, gaps)


def test_sample_time_quantiles_avoids_boundary_clustering():
    """구간 경계 근처(59~61초, 119~121초, 179~181초)에 프레임이 몰려 있어도,
    등분 경계를 사이에 둔 두 표본이 거의 같은 순간으로 뽑히지 않는다.

    개수 등분 + 완전 무작위였던 이전 로직의 핵심 결함(경계 몰림)에 대한
    회귀 테스트다. 배경으로 20초 간격 프레임도 섞어 둔다 - 실제 영상에서도
    특정 순간에만 프레임이 몰리고 나머지 구간이 완전히 비어 있지는 않다.
    """
    background = list(range(0, 241, 20))
    clusters = [59, 60, 61, 119, 120, 121, 179, 180, 181]
    metas = make_timed_metas(sorted(set(background + clusters)))

    for seed in range(30):
        picks = sample_time_quantiles(metas, 4, rng=random.Random(seed))
        vals = sorted(p.offset_seconds for p in picks)
        gaps = [b - a for a, b in zip(vals, vals[1:])]
        assert all(gap >= 5 for gap in gaps), (seed, vals, gaps)


def test_sample_time_quantiles_covers_sparse_tail():
    """앞쪽에 프레임이 밀집돼 있어도 표본이 앞쪽에만 쏠리지 않는다.

    프레임 30개가 0~60초에, 10개가 60~240초에 있다(선명도 필터가 초반에만
    프레임을 많이 남긴 상황을 흉내낸다). 개수 등분이었다면 30개 대 10개
    비중 때문에 표본 대부분이 앞 60초에 몰렸을 것이다.
    """
    front = [i * 60 / 29 for i in range(30)]
    back = [60 + i * 180 / 9 for i in range(10)]
    metas = make_timed_metas(front + back)

    for seed in range(10):
        picks = sample_time_quantiles(metas, 4, rng=random.Random(seed))
        back_count = sum(1 for p in picks if p.offset_seconds >= 60)
        assert back_count >= 2, (seed, [p.offset_seconds for p in picks])


def test_sample_time_quantiles_falls_back_without_offsets(capsys):
    """경과 시각을 모르는 프레임이 섞이면 시간 등분을 포기하고 경고 후
    개수 등분(폴백)으로도 n장을 채운다.
    """
    metas = make_metas(12)
    metas[5] = FrameMeta(path=metas[5].path, index=5, offset_seconds=None)

    picks = sample_time_quantiles(metas, 4, rng=random.Random(0))

    assert len(picks) == 4
    assert "경과 시각이 없는 프레임" in capsys.readouterr().err


# ------------------------------------------------------------ 촬영 일시 배선

def test_shot_datetime_computed_from_walk_start(tmp_path):
    """분할 전에 한 번도 발동하지 않았던 경로.

    프롬프트가 "촬영 일시가 주어졌다면 time_of_day는 그 값을 우선하고
    confidence를 1.0으로 한다"고 지시하는데, main()이 shot_datetime을
    넘기지 않아 항상 "불명"이었다.
    """
    walk = WalkInfo(date="2026-07-28", started_at="2026-07-28T08:12:03")
    metas = iter_frames(touch_frames(tmp_path / "f"), walk=walk)

    assert metas[0].shot_datetime == "2026-07-28 08:12:11"   # +8.53초
    assert metas[-1].shot_datetime == "2026-07-28 08:13:50"  # +107초
    assert metas[0].prompt_vars()["shot_datetime"] == "2026-07-28 08:12:11"


def test_shot_datetime_unknown_without_start(tmp_path):
    metas = iter_frames(touch_frames(tmp_path / "f"))
    assert all(m.shot_datetime == UNKNOWN for m in metas)


def test_bad_started_at_warns(tmp_path, capsys):
    walk = WalkInfo(started_at="2026년 7월 28일 오전 8시")
    metas = iter_frames(touch_frames(tmp_path / "f", REAL_NAMES[:1]), walk=walk)
    assert metas[0].shot_datetime == UNKNOWN
    assert "started_at 형식" in capsys.readouterr().err


def test_prompt_vars_keys_match_template():
    """prompt_vars()가 FRAME_EXTRACT의 템플릿 변수와 정확히 맞는지.

    이 테스트가 깨지면 payload 조립 시 KeyError가 난다.
    """
    from walklog import prompts as P

    meta = FrameMeta(path=Path("f_0000128_t000m08.53s.jpg"),
                     segment="seg_0000", offset_seconds=8.53,
                     shot_datetime="2026-07-28 08:12:11", location="OO천")
    rendered = P.FRAME_EXTRACT.render(**meta.prompt_vars())

    assert "seg_0000" in rendered
    assert "0분 9초" in rendered
    assert "2026-07-28 08:12:11" in rendered
    assert "OO천" in rendered


# ------------------------------------------------------------ manifest

def write_manifest(tmp_path, data):
    path = tmp_path / "manifest.json"
    path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    return path


def test_manifest_overrides_filename(tmp_path):
    directory = touch_frames(tmp_path / "f", REAL_NAMES[:2])
    manifest = write_manifest(tmp_path, {
        "walk": {"date": "2026-07-28", "started_at": "2026-07-28T08:12:03",
                 "location": "OO천 산책로"},
        "frames": [{"file": REAL_NAMES[0], "segment": "seg_0000",
                    "offset_seconds": 9.0}],
    })

    metas = iter_frames(directory, manifest=manifest)
    assert metas[0].segment == "seg_0000"
    assert metas[0].offset_seconds == pytest.approx(9.0)   # 파일명 8.53을 덮어씀
    assert metas[0].location == "OO천 산책로"
    # manifest에 없는 프레임은 파일명 파싱 결과를 그대로 쓴다.
    assert metas[1].offset_seconds == pytest.approx(10.67)
    assert metas[1].segment == UNKNOWN


@pytest.mark.parametrize("data,message", [
    ([1, 2, 3], "최상위는 객체"),
    ({"walk": "text"}, '"walk"는 객체'),
    ({"frames": {"a": 1}}, '"frames"는 배열'),
    ({"frames": [{"offset_seconds": 1}]}, '"file" 키가 없습니다'),
])
def test_manifest_bad_shape_reports_expected_format(tmp_path, data, message):
    """형식이 다르면 추측하지 않고 무엇을 기대하는지 알려준다."""
    with pytest.raises(ManifestError, match=message):
        load_manifest(write_manifest(tmp_path, data))


def test_manifest_missing_file(tmp_path):
    with pytest.raises(ManifestError, match="찾을 수 없습니다"):
        load_manifest(tmp_path / "nope.json")


# ------------------------------------------------------------ 기록 자료구조

def observation(**over):
    base = {"scene": "젖은 보도블록", "location_type": "공원", "weather": "비",
            "confidence": {"time_of_day": 0.6, "weather": 0.9, "location_type": 0.8},
            "unreadable": False}
    base.update(over)
    return base


def make_records(tmp_path, count=3):
    metas = iter_frames(touch_frames(tmp_path / "f", REAL_NAMES[:count]))
    return [FrameRecord(observation=observation(scene=f"장면 {i}"), meta=m)
            for i, m in enumerate(metas, 1)]


def test_unreadable_filter(tmp_path):
    records = make_records(tmp_path)
    records[1].observation["unreadable"] = True
    assert [r.observation["scene"] for r in usable(records)] == ["장면 1", "장면 3"]


def test_confidence_mean(tmp_path):
    record = make_records(tmp_path, 1)[0]
    assert record.confidence_mean == pytest.approx((0.6 + 0.9 + 0.8) / 3)
    record.observation["confidence"] = {}
    assert record.confidence_mean == 0.0


def test_to_json_lines_has_no_meta(tmp_path):
    """Stage 2 입력에는 관찰 결과만 들어간다(분할 전 동작과 동일)."""
    lines = to_json_lines(make_records(tmp_path)).splitlines()
    assert len(lines) == 3
    for line in lines:
        parsed = json.loads(line)
        assert "scene" in parsed
        assert not any(k in parsed for k in ("file", "elapsed", "segment", "_sort"))


def test_walk_duration(tmp_path):
    """마지막 프레임의 경과 시각이 산책 소요시간이 된다."""
    records = make_records(tmp_path, 3)   # 8.53s, 10.67s, 64.0s
    assert walk_duration(records) == "1분 4초"


def test_walk_duration_skips_unknown_tail(tmp_path):
    """마지막 프레임의 시각을 모르면 그 앞의 값을 쓴다."""
    metas = iter_frames(touch_frames(tmp_path / "f", REAL_NAMES[:2] + ["IMG_9.jpg"]))
    records = [FrameRecord(observation=observation(), meta=m) for m in metas]
    assert records[-1].meta.offset_seconds is None
    assert walk_duration(records) == "0분 11초"


# ------------------------------------------------------------ 저장 / 불러오기

def test_dump_load_round_trip(tmp_path):
    records = make_records(tmp_path)
    records[0].caption = "젖은 산책로"
    walk = WalkInfo(date="2026-07-28", started_at="2026-07-28T08:12:03",
                    location="OO천")
    out = dump_records(records, tmp_path / "out" / "frame_records.json",
                       walk=walk, prompt_version="2026-07-29")

    saved = json.loads(out.read_text(encoding="utf-8"))
    assert saved["schema"] == 1
    assert saved["frame_count"] == 3
    assert saved["prompt_version"] == "2026-07-29"
    assert saved["walk"]["started_at"] == "2026-07-28T08:12:03"

    loaded, loaded_walk = load_records(out, frame_dir=tmp_path / "f")
    assert [r.observation for r in loaded] == [r.observation for r in records]
    assert [r.meta.name for r in loaded] == [r.meta.name for r in records]
    assert [r.meta.offset_seconds for r in loaded] == [
        r.meta.offset_seconds for r in records]
    assert loaded[0].caption == "젖은 산책로"
    assert loaded_walk.location == "OO천"


def test_load_legacy_flat_format(tmp_path):
    """분할 전 frame_records.json 형식.

    관찰 결과 최상위에 "_elapsed", "_sort"가 섞여 있던 평면 배열이다.
    outputs/ 에 이미 쌓인 기록을 계속 읽을 수 있어야 한다.
    """
    legacy = [
        {**observation(scene="첫 장면"), "_elapsed": "0분 9초", "_sort": 8.53},
        {**observation(scene="두 번째"), "_elapsed": "1분 4초", "_sort": 64.0},
    ]
    path = tmp_path / "legacy.json"
    path.write_text(json.dumps(legacy, ensure_ascii=False), encoding="utf-8")

    records, walk = load_records(path)
    assert [r.observation["scene"] for r in records] == ["첫 장면", "두 번째"]
    assert records[0].meta.offset_seconds == pytest.approx(8.53)
    assert records[0].meta.elapsed == "0분 9초"
    # 내부 키가 관찰 결과에 남아 있지 않아야 한다.
    assert not any(k.startswith("_") for r in records for k in r.observation)
    assert walk.date == UNKNOWN


def test_load_rejects_unknown_shape(tmp_path):
    path = tmp_path / "weird.json"
    path.write_text('{"frames": {"a": 1}}', encoding="utf-8")
    with pytest.raises(RecordsError, match="records"):
        load_records(path)


def test_load_missing_and_broken(tmp_path):
    with pytest.raises(RecordsError, match="찾을 수 없습니다"):
        load_records(tmp_path / "nope.json")

    broken = tmp_path / "broken.json"
    broken.write_text("{not json", encoding="utf-8")
    with pytest.raises(RecordsError, match="올바른 JSON"):
        load_records(broken)