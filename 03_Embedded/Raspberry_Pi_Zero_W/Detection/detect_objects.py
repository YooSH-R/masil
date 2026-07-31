#!/usr/bin/env python3
"""
detect_objects.py - 추출된 프레임에서 YOLO로 객체 탐지

extract_best_frames.py가 뽑아낸 구간별 최선 프레임들에 대해
YOLO(Ultralytics) 모델로 객체를 탐지하고, 박스를 그린 이미지와
탐지 결과(JSON)를 저장합니다.

설치
    pip install ultralytics

사용법
    python3 detect_objects.py frames/ -o detections/
    python3 detect_objects.py frames/ -o detections/ --model yolov8n.pt --conf 0.25
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import cv2

if sys.platform == "win32":
    for _stream in (sys.stdout, sys.stderr):
        try:
            _stream.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            pass

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png"}

DEFAULT_MODEL = "yolov8n.pt"
DEFAULT_CONF = 0.25


def find_images(input_dir: Path) -> list[Path]:
    return sorted(
        p for p in input_dir.rglob("*")
        if p.suffix.lower() in IMAGE_SUFFIXES
    )


def detect(
    input_dir: Path,
    output_dir: Path,
    model_name: str,
    conf: float,
) -> dict:
    from ultralytics import YOLO

    images = find_images(input_dir)
    if not images:
        raise RuntimeError(f"입력 폴더에 이미지가 없습니다: {input_dir}")

    print(f"입력 폴더 : {input_dir}")
    print(f"이미지 수 : {len(images)}장")
    print(f"모델      : {model_name}")
    print(f"신뢰도 임계값: {conf}")
    print()

    model = YOLO(model_name)

    summary: dict = {
        "input": str(input_dir),
        "model": model_name,
        "conf_threshold": conf,
        "images": [],
    }
    total_detections = 0

    for i, img_path in enumerate(images, 1):
        rel = img_path.relative_to(input_dir)
        out_path = output_dir / rel
        out_path.parent.mkdir(parents=True, exist_ok=True)

        result = model.predict(str(img_path), conf=conf, verbose=False)[0]

        annotated = result.plot()
        cv2.imwrite(str(out_path), annotated)

        boxes = []
        for box in result.boxes:
            cls_id = int(box.cls[0])
            boxes.append({
                "class": result.names[cls_id],
                "confidence": round(float(box.conf[0]), 4),
                "bbox_xyxy": [round(v, 1) for v in box.xyxy[0].tolist()],
            })

        total_detections += len(boxes)
        summary["images"].append({
            "file": str(rel).replace("\\", "/"),
            "detections": boxes,
        })

        print(f"\r진행 {i}/{len(images)}  ({rel} → 탐지 {len(boxes)}개)"
              + " " * 10, end="", flush=True)

    print("\r" + " " * 80 + "\r", end="")

    summary["total_detections"] = total_detections
    summary["total_images"] = len(images)
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "detections.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False)
    )
    return summary


def main() -> int:
    p = argparse.ArgumentParser(
        description="이미지 폴더에서 YOLO로 객체를 탐지하고 박스를 그려 저장"
    )
    p.add_argument("input", type=Path, help="입력 이미지 폴더 (하위 폴더 포함 탐색)")
    p.add_argument("-o", "--output", type=Path, default=Path("detections"),
                   help="출력 폴더 (기본: detections/)")
    p.add_argument("--model", type=str, default=DEFAULT_MODEL,
                   help=f"YOLO 모델. 기본 {DEFAULT_MODEL} (최초 실행 시 자동 다운로드)")
    p.add_argument("--conf", type=float, default=DEFAULT_CONF,
                   help=f"신뢰도 임계값. 기본 {DEFAULT_CONF}")
    args = p.parse_args()

    if not args.input.exists():
        print(f"오류: 입력 폴더가 없습니다 — {args.input}", file=sys.stderr)
        return 1

    try:
        s = detect(
            input_dir=args.input,
            output_dir=args.output,
            model_name=args.model,
            conf=args.conf,
        )
    except RuntimeError as e:
        print(f"오류: {e}", file=sys.stderr)
        return 1

    per_class: dict[str, int] = {}
    for img in s["images"]:
        for d in img["detections"]:
            per_class[d["class"]] = per_class.get(d["class"], 0) + 1

    print("─" * 52)
    print(f"처리한 이미지 : {s['total_images']}장")
    print(f"총 탐지 수    : {s['total_detections']}개")
    if per_class:
        print("클래스별 탐지 수:")
        for name, count in sorted(per_class.items(), key=lambda x: -x[1]):
            print(f"  {name:<15}: {count}")
    print(f"출력 위치     : {args.output}")
    print(f"결과 파일     : {args.output / 'detections.json'}")
    print("─" * 52)
    return 0


if __name__ == "__main__":
    sys.exit(main())
