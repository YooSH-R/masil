"""extract_best_frames.py 검증. 실영상 없이 합성 mp4로 동작을 확인한다.

cv2.VideoWriter로 64x64 흑백 노이즈/균일 프레임을 섞어 만든 짧은 영상을
tmp_path에 만들고, 그 결과로 다음을 확인한다.

  1. --max-frames가 구간 길이를 총 길이에서 역산하고 저장 장수 상한을 지킨다
  2. --max-frames 0이면 기존 고정 구간 동작 그대로다
  3. --stride는 건너뛴 프레임도 frame_index를 계속 늘리며, 저장되는 구간이
     stride=1과 같아야 한다(피크 프레임을 stride의 배수 위치에 둬서 보장)
  4. 최소 저장 간격 필터가 구간 경계에 붙은 두 피크를 하나만 남긴다
  5. manifest에 max_frames / window_sec / stride가 기록된다
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import cv2
import numpy as np
import pytest

MODULE_PATH = Path(__file__).with_name("extract_best_frames.py")


def _load_module():
    spec = importlib.util.spec_from_file_location("extract_best_frames", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


ebf = _load_module()

FPS = 15.0
SIZE = (64, 64)


def make_video(path: Path, total_frames: int, peak_frames: set,
                fps: float = FPS, size=SIZE, seed: int = 0) -> None:
    """피크 프레임은 고대비 노이즈, 나머지는 균일 회색인 합성 영상.

    균일 회색 프레임끼리는 선명도 점수가 항상 0에 가까워 절대 1등이 될 수
    없고, 피크 프레임은 노이즈라 선명도 점수가 확실히 높다. 어떤 구간이든
    피크가 있으면 그 프레임이 선택된다는 걸 코드로 보장하는 방식이다.
    """
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(str(path), fourcc, fps, size)
    rng = np.random.default_rng(seed)
    for i in range(total_frames):
        if i in peak_frames:
            frame = rng.integers(0, 256, size=(size[1], size[0], 3), dtype=np.uint8)
        else:
            frame = np.full((size[1], size[0], 3), 128, dtype=np.uint8)
        writer.write(frame)
    writer.release()


def run_extract(video_path: Path, output_dir: Path, **kwargs):
    defaults = dict(
        video_path=video_path,
        output_dir=output_dir,
        window_sec=ebf.DEFAULT_WINDOW_SEC,
        metric_name="laplacian",
        center_crop=1.0,
        dedup=True,
        dedup_threshold=ebf.DEDUP_THRESHOLD,
        min_sharpness=0.0,
        start_wall=None,
        max_frames=0,
        stride=1,
    )
    defaults.update(kwargs)
    return ebf.extract(**defaults)


# ------------------------------------------------------------ --max-frames

def test_max_frames_caps_saved_count_and_computes_window(tmp_path):
    """60초 영상, 10초마다 피크 하나씩 6개. --max-frames 6이면 window_sec≈10."""
    total = int(60 * FPS)
    peaks = {w * int(10 * FPS) for w in range(6)}
    video = tmp_path / "in.mp4"
    make_video(video, total, peaks)

    manifest = run_extract(video, tmp_path / "out", max_frames=6)

    assert manifest["max_frames"] == 6
    assert manifest["window_sec"] == pytest.approx(10.0, abs=0.5)
    assert len(manifest["frames"]) <= 6
    assert len(manifest["frames"]) == 6  # 피크가 정확히 6개 구간에 하나씩 있다


def test_max_frames_zero_keeps_fixed_window_behavior(tmp_path):
    """--max-frames 0 --window 5 는 기존 고정 구간 동작. 60초/5초 = 12구간."""
    total = int(60 * FPS)
    peaks = {w * int(10 * FPS) for w in range(6)}
    video = tmp_path / "in.mp4"
    make_video(video, total, peaks)

    manifest = run_extract(video, tmp_path / "out", max_frames=0, window_sec=5.0)

    assert manifest["window_sec"] == 5.0
    assert manifest["stats"]["windows"] == 12


# ------------------------------------------------------------ --stride

def test_stride_advances_frame_index_through_skipped_frames(tmp_path):
    """건너뛴 프레임도 frame_index(=timestamp 기준)가 계속 늘어야 한다."""
    total = int(20 * FPS)
    video = tmp_path / "in.mp4"
    make_video(video, total, peak_frames=set())

    manifest = run_extract(video, tmp_path / "out", stride=3)

    assert manifest["frames_read"] == total


def test_stride_matches_stride_one_window_distribution(tmp_path):
    """피크를 stride의 배수 위치에 두면, stride=3에서도 같은 구간이 저장된다."""
    total = int(60 * FPS)
    window_frames = int(10 * FPS)  # 150, 3의 배수
    peaks = {w * window_frames for w in range(6)}
    video = tmp_path / "in.mp4"
    make_video(video, total, peaks)

    baseline = run_extract(video, tmp_path / "out1", stride=1)
    strided = run_extract(video, tmp_path / "out2", stride=3)

    assert strided["stride"] == 3
    assert strided["frames_read"] == baseline["frames_read"]

    base_windows = {f["frame_index"] // window_frames for f in baseline["frames"]}
    stride_windows = {f["frame_index"] // window_frames for f in strided["frames"]}
    assert stride_windows == base_windows
    assert len(strided["frames"]) == len(baseline["frames"])


# ------------------------------------------------------------ 최소 저장 간격

def test_minimum_gap_filters_boundary_pair(tmp_path):
    """구간 경계 바로 앞/뒤에 붙은 두 피크는 하나만 저장돼야 한다.

    window_sec=5초 -> 최소 간격 1.5초. 경계(5.0s)를 사이에 둔 피크 두 개를
    ~0.13초 간격으로 배치해 실제 버그(1초 간격 쌍)를 재현한다. 두 피크는
    서로 다른 노이즈라 dedup(내용 유사성, 임계값 6.0)은 통과하므로
    시간 간격 필터만이 이 쌍을 잡을 수 있다.
    """
    fps = FPS
    window_sec = 5.0
    boundary_frame = int(window_sec * fps)  # 75
    total = int(20 * fps)
    peaks = {boundary_frame - 1, boundary_frame + 1}
    video = tmp_path / "in.mp4"
    make_video(video, total, peaks, seed=1)

    manifest = run_extract(video, tmp_path / "out", window_sec=window_sec)

    ts = sorted(f["timestamp_sec"] for f in manifest["frames"])
    gaps = [b - a for a, b in zip(ts, ts[1:])]
    min_gap = window_sec * ebf.MIN_GAP_RATIO
    assert all(gap >= min_gap - 1e-9 for gap in gaps), gaps
    assert manifest["stats"]["skipped_close"] >= 1
    # 두 피크 중 하나만 살아남는다(둘 다 버려지진 않는다).
    assert any(abs(t - (boundary_frame - 1) / fps) < 0.01
               or abs(t - (boundary_frame + 1) / fps) < 0.01 for t in ts)


# ------------------------------------------------------------ manifest 필드

def test_manifest_records_new_fields(tmp_path):
    total = int(20 * FPS)
    video = tmp_path / "in.mp4"
    make_video(video, total, peak_frames={10, 40})

    manifest = run_extract(video, tmp_path / "out", max_frames=4, stride=2)

    assert manifest["max_frames"] == 4
    assert manifest["stride"] == 2
    assert "window_sec" in manifest
