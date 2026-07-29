"""records.py 검증.

무게중심은 세 가지다.
  1. 실제 프레임 파일명(f_0000128_t000m08.53s.jpg)을 정확히 해석하는가
  2. 파싱 실패가 조용히 넘어가지 않는가
  3. 분할 전 frame_records.json을 계속 읽을 수 있는가
"""

from __future__ import annotations

import json
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