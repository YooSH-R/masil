#!/usr/bin/env python3
"""
extract_best_frames.py - 영상에서 구간별 최선 프레임 추출

산책 영상에서 번짐이 적고 노출이 정상인 프레임만 골라 저장합니다.
PC 또는 Jetson에서 실행하세요. Pi Zero W에서는 돌리지 마세요.

핵심 설계
    선명도 점수(라플라시안 분산)는 장면 내용에 크게 좌우되므로
    영상 전체를 놓고 절대 비교하면 안 됩니다.
    "텍스처가 많은 장면"이 "선명한 장면"보다 높은 점수를 받습니다.

    따라서 짧은 시간 구간(기본 10초) 안에서만 상대 비교하여
    구간별 1등을 뽑습니다. 같은 구간 안에서는 장면이 비슷하므로
    점수 차이가 곧 번짐 차이가 됩니다.

필터 4단계
    1. 노출   - 하이라이트 클리핑, 암부 뭉개짐 프레임 배제 (외1 대응)
    2. 선명도 - 구간 내 라플라시안 분산 최댓값 선택 (외2 대응)
    3. 중복   - 직전 선택분과 내용이 너무 비슷하면 건너뜀 (외7 대응)
    4. 간격   - 직전 선택분과 시간이 너무 가까우면 건너뜀 (구간 경계 몰림 대응)

--max-frames로 목표 장수 상한을 주면 구간 길이를 영상 총 길이에서 역산합니다.
--stride로 평가 간격을 늘리면 건너뛰는 프레임은 디코딩 없이(cap.grab())
넘어가 처리 시간을 줄입니다.
--clean을 주면 추출 전에 출력 폴더의 이전 산출물(f_*.jpg, manifest.json)을
지웁니다. 자동화 경로(세션 재처리)에서 이전 실행의 프레임이 새 manifest와
섞이는 것을 막습니다. 이 스크립트가 만들지 않은 파일은 건드리지 않습니다.

설치
    pip install opencv-python numpy

사용법
    python3 extract_best_frames.py walk.mp4 -o frames/
    python3 extract_best_frames.py walk.mp4 -o frames/ --window 5
    python3 extract_best_frames.py walk.mp4 -o frames/ --metric tenengrad
    python3 extract_best_frames.py walk.mp4 -o frames/ --no-dedup
    python3 extract_best_frames.py walk.mp4 -o frames/ --max-frames 48 --stride 3
    python3 extract_best_frames.py walk.mp4 -o frames/ --clean
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta
from pathlib import Path

import cv2
import numpy as np

# Windows 콘솔이 cp949 등 비UTF-8 코드페이지일 때 한글 출력이 깨지는 것을 방지.
if sys.platform == "win32":
    for _stream in (sys.stdout, sys.stderr):
        try:
            _stream.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            pass

# ─────────────────────────────────────────────────────────
# 기본값
# ─────────────────────────────────────────────────────────

DEFAULT_WINDOW_SEC = 10.0

# --max-frames 기본값. 하류(walklog)는 4~8장만 표본화해 쓰므로
# 30~60장이면 충분하다.
DEFAULT_MAX_FRAMES = 48

# --stride 기본값. 1이면 전 프레임 평가(기존 동작).
DEFAULT_STRIDE = 1

# 노출 판정. 이 비율을 넘으면 해당 프레임을 후보에서 제외합니다.
# 자동 노출이 재수렴하는 동안 촬영된 프레임이 여기 걸립니다.
CLIP_HIGH_LIMIT = 0.12      # 밝기 250 이상 픽셀 비율
CLIP_LOW_LIMIT = 0.35       # 밝기 8 이하 픽셀 비율

# 중복 판정. 32x32로 줄인 뒤 평균 절대 차이가 이 값 미만이면 중복.
DEDUP_THRESHOLD = 6.0

# 직전 저장분과의 최소 시간 간격 (구간 길이 대비 비율).
# 인접 구간의 1등이 경계 양쪽에 붙으면 같은 순간이 두 장 저장된다.
# dedup은 내용 기준이라 카메라가 움직이면 통과하므로 시간 기준을 병행한다.
MIN_GAP_RATIO = 0.3

# 구간 전체가 쓸모없을 때 버리는 하한선.
# 0이면 비활성. 실제 영상으로 점수 분포를 본 뒤 정하는 것을 권합니다.
MIN_SHARPNESS = 0.0

JPEG_QUALITY = 95


# ─────────────────────────────────────────────────────────
# 품질 측정
# ─────────────────────────────────────────────────────────


def sharpness_laplacian(gray: np.ndarray) -> float:
    """라플라시안 분산. 가장 널리 쓰이는 번짐 지표입니다."""
    return float(cv2.Laplacian(gray, cv2.CV_64F).var())


def sharpness_tenengrad(gray: np.ndarray) -> float:
    """소벨 기울기 크기의 평균. 노이즈에 라플라시안보다 강합니다."""
    gx = cv2.Sobel(gray, cv2.CV_64F, 1, 0, ksize=3)
    gy = cv2.Sobel(gray, cv2.CV_64F, 0, 1, ksize=3)
    return float(np.mean(gx * gx + gy * gy))


METRICS = {
    "laplacian": sharpness_laplacian,
    "tenengrad": sharpness_tenengrad,
}


def exposure_stats(gray: np.ndarray) -> tuple[float, float, float]:
    """(하이라이트 클리핑 비율, 암부 뭉개짐 비율, 평균 밝기)"""
    total = gray.size
    high = float(np.count_nonzero(gray >= 250)) / total
    low = float(np.count_nonzero(gray <= 8)) / total
    return high, low, float(gray.mean())


def thumbnail(gray: np.ndarray) -> np.ndarray:
    """중복 판정용 축소본."""
    return cv2.resize(gray, (32, 32), interpolation=cv2.INTER_AREA).astype(np.int16)


# ─────────────────────────────────────────────────────────
# 출력 폴더 초기화
# ─────────────────────────────────────────────────────────


def clean_outputs(output_dir: Path) -> int:
    """출력 폴더에서 이 스크립트의 이전 산출물만 지운다.

    폴더를 통째로 지우지 않는 이유: 잘못된 경로(-o ~ 같은)가 넘어와도
    이 스크립트가 만든 파일(f_*.jpg, manifest.json) 외에는 아무것도
    잃지 않게 하기 위해서다. 세션 재처리(FAILED -> TRANSFER_DONE 복귀)
    시 이전 실행의 프레임이 새 manifest와 섞여 하류(walklog)가 잘못된
    기록을 만드는 것을 막는다.

    반환값은 삭제한 파일 수. output_dir이 없으면 0을 반환한다.
    """
    if not output_dir.is_dir():
        return 0
    removed = 0
    for path in sorted(output_dir.glob("f_*.jpg")):
        path.unlink()
        removed += 1
    manifest_path = output_dir / "manifest.json"
    if manifest_path.is_file():
        manifest_path.unlink()
        removed += 1
    return removed


# ─────────────────────────────────────────────────────────


@dataclass
class Candidate:
    frame_index: int
    timestamp_sec: float
    score: float
    clip_high: float
    clip_low: float
    mean_brightness: float


class WindowSelector:
    """한 시간 구간 안에서 최선 프레임 하나를 유지합니다.

    프레임 전체를 메모리에 쌓지 않고, 현재 1등만 들고 있습니다.
    2시간 영상(10만 프레임)도 메모리 사용량이 일정합니다.
    """

    def __init__(self):
        self.best: Candidate | None = None
        self.best_image: np.ndarray | None = None
        self.best_thumb: np.ndarray | None = None
        self.evaluated = 0
        self.rejected_exposure = 0

    def offer(
        self,
        frame_bgr: np.ndarray,
        gray: np.ndarray,
        cand: Candidate,
        exposure_ok: bool,
    ) -> None:
        self.evaluated += 1
        if not exposure_ok:
            self.rejected_exposure += 1
            return
        if self.best is None or cand.score > self.best.score:
            self.best = cand
            self.best_image = frame_bgr.copy()
            self.best_thumb = thumbnail(gray)


# ─────────────────────────────────────────────────────────


def extract(
    video_path: Path,
    output_dir: Path,
    window_sec: float,
    metric_name: str,
    center_crop: float,
    dedup: bool,
    dedup_threshold: float,
    min_sharpness: float,
    start_wall: datetime | None,
    fps_override: float | None = None,
    max_frames: int = 0,
    stride: int = 1,
    clean: bool = False,
) -> dict:
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise RuntimeError(f"영상을 열 수 없습니다: {video_path}")

    raw_suffixes = {".h264", ".264", ".h265", ".hevc", ".raw"}
    is_raw_stream = video_path.suffix.lower() in raw_suffixes

    if fps_override is not None:
        fps = fps_override
    else:
        fps = cap.get(cv2.CAP_PROP_FPS)
        # 원시 스트림에는 프레임레이트 정보가 없습니다.
        # OpenCV가 조용히 25.0 같은 기본값을 반환하므로,
        # 값이 그럴듯해 보여도 신뢰할 수 없습니다.
        if is_raw_stream:
            cap.release()
            raise RuntimeError(
                f"원시 스트림({video_path.suffix})에는 프레임레이트 정보가 없습니다.\n"
                f"  OpenCV가 반환한 값 {fps:.2f} fps는 실제 값이 아닐 수 있습니다.\n\n"
                "  해결 방법 1 — mp4로 변환 (권장):\n"
                "    ffmpeg -f h264 -r 15 -i in.h264 -c copy out.mp4\n\n"
                "  해결 방법 2 — 프레임레이트 직접 지정:\n"
                "    --fps 15"
            )
        if not fps or fps <= 0 or fps > 1000:
            cap.release()
            raise RuntimeError(
                f"프레임레이트를 읽을 수 없습니다 (읽은 값: {fps}). "
                "--fps 로 직접 지정하세요."
            )

    # CAP_PROP_FRAME_COUNT는 컨테이너에 따라 음수나 터무니없는 값을
    # 반환합니다. 진행률 표시에만 쓰므로, 이상하면 미상으로 처리합니다.
    raw_count = cap.get(cv2.CAP_PROP_FRAME_COUNT)
    total_frames = int(raw_count) if 0 < raw_count < 100_000_000 else 0

    # --max-frames 활성 시 window_sec를 총 길이에서 역산한다.
    # window_sec(함수 인자로 받은 --window 값)는 이 모드에서 구간 하한이 된다.
    window_floor = window_sec
    max_frames_applied = False
    if max_frames > 0:
        if total_frames > 0:
            total_duration = total_frames / fps
            window_sec = max(total_duration / max_frames, window_floor)
            max_frames_applied = True
        else:
            print(
                f"경고: 총 프레임 수를 알 수 없어 --max-frames를 적용할 수 없습니다. "
                f"고정 구간({window_floor:.1f}초)으로 진행합니다.",
                file=sys.stderr,
            )

    metric = METRICS[metric_name]
    output_dir.mkdir(parents=True, exist_ok=True)

    # 이전 실행 산출물 초기화. 영상을 열고 fps 검증까지 끝난 뒤에 지운다 -
    # 입력이 잘못된 실행(파일 없음, fps 미상)이 기존 산출물만 날리고
    # 새 결과는 못 만드는 최악의 순서를 피하기 위해서다.
    if clean:
        removed = clean_outputs(output_dir)
        if removed:
            print(f"초기화      : 이전 산출물 {removed}개 삭제 "
                  f"(f_*.jpg, manifest.json)")

    print(f"입력      : {video_path}")
    print(f"프레임레이트: {fps:.2f} fps"
          + (" (직접 지정)" if fps_override is not None else ""))
    if total_frames:
        print(f"총 프레임 : {total_frames:,}장 ({total_frames / fps / 60:.1f}분)")
    else:
        print("총 프레임 : 미상 (진행률 표시 생략)")
    if max_frames_applied:
        print(f"구간 길이 : {window_sec:.1f}초 (--max-frames {max_frames} 기준 자동 계산)")
    else:
        print(f"구간 길이 : {window_sec:.1f}초")
    print(f"측정 방식 : {metric_name}")
    if stride > 1:
        print(f"평가 스트라이드: {stride}프레임마다 1장")
    print()

    selector = WindowSelector()
    current_window = 0
    frame_index = 0
    saved: list[dict] = []
    prev_thumb: np.ndarray | None = None
    last_saved_ts: float | None = None
    stats = {"windows": 0, "saved": 0, "skipped_dup": 0,
             "skipped_low": 0, "skipped_close": 0, "rejected_exposure": 0}

    def flush_window() -> None:
        nonlocal prev_thumb, last_saved_ts
        if selector.best is None:
            return
        stats["rejected_exposure"] += selector.rejected_exposure

        cand = selector.best

        if min_sharpness > 0 and cand.score < min_sharpness:
            stats["skipped_low"] += 1
            return

        if dedup and prev_thumb is not None:
            diff = float(np.mean(np.abs(selector.best_thumb - prev_thumb)))
            if diff < dedup_threshold:
                stats["skipped_dup"] += 1
                return

        if (last_saved_ts is not None
                and cand.timestamp_sec < last_saved_ts + window_sec * MIN_GAP_RATIO):
            stats["skipped_close"] += 1
            return

        ts = cand.timestamp_sec
        name = f"f_{cand.frame_index:07d}_t{int(ts // 60):03d}m{ts % 60:05.2f}s.jpg"
        path = output_dir / name
        cv2.imwrite(str(path), selector.best_image,
                    [int(cv2.IMWRITE_JPEG_QUALITY), JPEG_QUALITY])

        record = asdict(cand)
        record["file"] = name
        if start_wall is not None:
            record["wall_time"] = (
                start_wall + timedelta(seconds=ts)
            ).isoformat(timespec="seconds")
        saved.append(record)
        prev_thumb = selector.best_thumb
        last_saved_ts = ts
        stats["saved"] += 1

    def report_progress() -> None:
        if total_frames and frame_index % 1000 == 0:
            pct = frame_index / total_frames * 100
            print(f"\r진행 {pct:5.1f}%  ({frame_index:,}/{total_frames:,})",
                  end="", flush=True)

    while True:
        if stride > 1 and frame_index % stride != 0:
            if not cap.grab():
                break
            frame_index += 1
            report_progress()
            continue

        ok, frame = cap.read()
        if not ok:
            break

        timestamp = frame_index / fps
        window_id = int(timestamp // window_sec)

        if window_id != current_window:
            flush_window()
            stats["windows"] += 1
            selector = WindowSelector()
            current_window = window_id

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

        if center_crop < 1.0:
            h, w = gray.shape
            ch, cw = int(h * center_crop), int(w * center_crop)
            y0, x0 = (h - ch) // 2, (w - cw) // 2
            region = gray[y0:y0 + ch, x0:x0 + cw]
        else:
            region = gray

        clip_high, clip_low, mean_b = exposure_stats(gray)
        exposure_ok = (clip_high < CLIP_HIGH_LIMIT and clip_low < CLIP_LOW_LIMIT)

        selector.offer(
            frame, gray,
            Candidate(
                frame_index=frame_index,
                timestamp_sec=round(timestamp, 3),
                score=round(metric(region), 2),
                clip_high=round(clip_high, 4),
                clip_low=round(clip_low, 4),
                mean_brightness=round(mean_b, 1),
            ),
            exposure_ok,
        )

        frame_index += 1
        report_progress()

    flush_window()
    stats["windows"] += 1
    cap.release()
    print("\r" + " " * 50 + "\r", end="")

    manifest = {
        "source": str(video_path),
        "fps": round(fps, 3),
        "frames_read": frame_index,
        "window_sec": window_sec,
        "max_frames": max_frames,
        "stride": stride,
        "metric": metric_name,
        "center_crop": center_crop,
        "stats": stats,
        "frames": saved,
    }
    (output_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False)
    )
    return manifest


# ─────────────────────────────────────────────────────────


def main() -> int:
    p = argparse.ArgumentParser(
        description="영상에서 구간별로 가장 선명한 프레임 추출"
    )
    p.add_argument("video", type=Path, help="입력 영상 (mp4 권장)")
    p.add_argument("-o", "--output", type=Path, default=Path("frames"),
                   help="출력 폴더 (기본: frames/)")
    p.add_argument("--window", type=float, default=DEFAULT_WINDOW_SEC,
                   help=f"구간 길이(초). --max-frames 비활성(0) 시 고정 구간 길이로 "
                        f"쓰인다. --max-frames 활성 시에는 구간 길이 하한이 된다. "
                        f"기본 {DEFAULT_WINDOW_SEC:.0f}")
    p.add_argument("--fps", type=float, default=None,
                   help="프레임레이트 직접 지정. 원시 h264 입력 시 필수")
    p.add_argument("--metric", choices=list(METRICS), default="laplacian",
                   help="선명도 측정 방식")
    p.add_argument("--center-crop", type=float, default=1.0,
                   help="중앙 영역만 평가 (예: 0.6). 기본 1.0=전체")
    p.add_argument("--no-dedup", action="store_true",
                   help="중복 프레임 제거 비활성화")
    p.add_argument("--dedup-threshold", type=float, default=DEDUP_THRESHOLD,
                   help=f"중복 판정 기준. 기본 {DEDUP_THRESHOLD}")
    p.add_argument("--min-sharpness", type=float, default=MIN_SHARPNESS,
                   help="이 점수 미만인 구간은 버림. 0이면 비활성")
    p.add_argument("--start-time", type=str, default=None,
                   help="촬영 시작 시각 (ISO 형식). 프레임별 실제 시각 계산용")
    p.add_argument("--max-frames", type=int, default=DEFAULT_MAX_FRAMES,
                   help="목표 저장 장수 상한. 영상 총 길이에서 구간 길이를 역산한다 "
                        "(--window는 구간 길이 하한이 됨). dedup/노출/최소 간격 "
                        "필터로 실제 저장 장수는 이보다 적을 수 있다. 0이면 비활성"
                        f"(고정 구간 동작). 기본 {DEFAULT_MAX_FRAMES}")
    p.add_argument("--stride", type=int, default=DEFAULT_STRIDE,
                   help="평가 스트라이드. K>1이면 K프레임마다 1장만 평가해 디코딩을 "
                        "아낀다. 15fps 영상이면 2~3 권장 — 인접 프레임의 선명도는 "
                        f"거의 같아 구간 1등 품질에 영향이 미미하다. 기본 {DEFAULT_STRIDE}")
    p.add_argument("--clean", action="store_true",
                   help="추출 전에 출력 폴더의 이전 산출물(f_*.jpg, manifest.json)을 "
                        "삭제한다. 이 스크립트가 만들지 않은 파일은 건드리지 않는다. "
                        "세션 재처리 자동화 경로에서 사용을 권장")
    args = p.parse_args()

    if not args.video.exists():
        print(f"오류: 파일이 없습니다 — {args.video}", file=sys.stderr)
        return 1

    if args.max_frames < 0:
        print("오류: --max-frames는 0 이상이어야 합니다", file=sys.stderr)
        return 1

    if args.stride < 1:
        print("오류: --stride는 1 이상이어야 합니다", file=sys.stderr)
        return 1

    if not (0.1 <= args.center_crop <= 1.0):
        print("오류: --center-crop은 0.1~1.0 범위여야 합니다", file=sys.stderr)
        return 1

    start_wall = None
    if args.start_time:
        try:
            start_wall = datetime.fromisoformat(args.start_time)
        except ValueError:
            print(f"오류: 시각 형식이 잘못되었습니다 — {args.start_time}",
                  file=sys.stderr)
            return 1

    try:
        m = extract(
            video_path=args.video,
            output_dir=args.output,
            window_sec=args.window,
            metric_name=args.metric,
            center_crop=args.center_crop,
            dedup=not args.no_dedup,
            dedup_threshold=args.dedup_threshold,
            min_sharpness=args.min_sharpness,
            start_wall=start_wall,
            fps_override=args.fps,
            max_frames=args.max_frames,
            stride=args.stride,
            clean=args.clean,
        )
    except RuntimeError as e:
        print(f"오류: {e}", file=sys.stderr)
        return 1

    s = m["stats"]
    print("─" * 52)
    print(f"읽은 프레임   : {m['frames_read']:,}장")
    print(f"구간 수       : {s['windows']}개")
    print(f"저장된 프레임 : {s['saved']}장")
    print(f"  중복 제외   : {s['skipped_dup']}개 구간")
    print(f"  선명도 미달 : {s['skipped_low']}개 구간")
    print(f"  간격 미달   : {s['skipped_close']}개 구간")
    print(f"  노출 불량   : {s['rejected_exposure']:,}프레임 후보 제외")
    if m["frames_read"]:
        ratio = s["saved"] / m["frames_read"] * 100
        print(f"추출 비율     : {ratio:.3f}%")
    print(f"출력 위치     : {args.output}")
    print(f"목록 파일     : {args.output / 'manifest.json'}")
    print("─" * 52)

    if s["saved"] == 0:
        print("\n경고: 저장된 프레임이 없습니다.")
        print("      --no-dedup 또는 --min-sharpness 0 으로 재시도해 보세요.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())