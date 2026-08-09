"""파이프라인 단계.

  observe.py     Stage 1  프레임 -> 관찰 기록          (VLM)
  compose.py     Stage 2  관찰 기록 -> 산책 일지        (LLM)
  illustrate.py  Stage 3  관찰 기록 -> 삽화 -> 스토리보드 (LLM + 이미지 모델 + Pillow)

모든 단계 함수는 GMSClient를 첫 인자로 받는다.
전역 클라이언트를 참조하면 가짜 클라이언트를 꽂아 테스트할 수 없다.
"""

from __future__ import annotations

from .compose import ComposeError, compose_walk_log
from .illustrate import (
    IllustrateError,
    KeyScene,
    build_journal,
    build_panels,
    build_single_image,
    build_story_image,
    build_storyboard,
    compose_journal,
    compose_storyboard,
    event_score,
    scene_changed,
    select_key_events,
    select_key_scenes,
)
from .observe import FrameFailure, observe_frame, observe_frames, observe_outdoor_frames

__all__ = [
    "observe_frame",
    "observe_frames",
    "observe_outdoor_frames",
    "FrameFailure",
    "compose_walk_log",
    "ComposeError",
    "select_key_scenes",
    "select_key_events",
    "event_score",
    "scene_changed",
    "KeyScene",
    "build_storyboard",
    "build_single_image",
    "build_story_image",
    "build_journal",
    "build_panels",
    "compose_storyboard",
    "compose_journal",
    "IllustrateError",
]