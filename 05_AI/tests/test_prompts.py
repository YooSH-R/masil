"""분할 전 prompts.py와 분할 후 walklog.prompts가 완전히 같은 프롬프트를 만드는지 검증.

프롬프트 리팩터링은 LLM 출력으로 검증할 수 없다(비결정적이다).
검증 가능한 것은 "모델에게 전달되는 문자열이 한 글자도 안 바뀌었다"이므로 그것만 본다.

사용:
    python verify_prompt_split.py path/to/old_prompts.py
    (인자를 생략하면 ./prompts_original.py 를 찾는다)
"""

from __future__ import annotations

import difflib
import importlib.util
import json
import sys
from pathlib import Path

SPEC_FIELDS = ("system", "user_template", "temperature",
               "max_output_tokens", "response_schema", "examples")

# 분할 이후 "의도적으로" 바꾼 값. {(라벨, 필드): (분할 전, 현재)}
#
# 안전망을 없애지 않기 위해 허용 목록으로 관리한다. 여기 없는 차이는 실수이며
# 즉시 실패한다. 여기 있는 항목도 값이 정확히 일치해야 통과한다.
INTENTIONAL: dict[tuple[str, str], tuple[object, object]] = {
    # 사고 토큰이 출력 예산을 먼저 소진해 finishReason=MAX_TOKENS로 응답이
    # 비어 오는 사고가 실제로 발생했다(삽화 3장 생성 후 캡션에서 중단).
    # max_output_tokens는 상한일 뿐 실제 생성량만 과금되므로 넉넉히 둔다.
    ("PANEL_CAPTION_WRITER", "max_output_tokens"): (64, 1024),
    ("IMAGE_PROMPT_WRITER", "max_output_tokens"): (512, 1024),
    ("FLOW_IMAGE_WRITER", "max_output_tokens"): (512, 1024),
    ("REGISTRY['panel_caption_writer']", "max_output_tokens"): (64, 1024),
    ("REGISTRY['image_prompt_writer']", "max_output_tokens"): (512, 1024),
    ("REGISTRY['flow_image_writer']", "max_output_tokens"): (512, 1024),

    # thinking 모델(gemini-3.5-flash)은 사고 토큰이 출력 예산을 먼저 소진한다.
    # 2048이면 일지 본문이 MAX_TOKENS로 잘린다(require_text()가 이제 이를 감지해
    # 예외를 던진다). 분량은 [문체] 프리셋의 글자 수 지시가 통제하므로 상한을
    # 올려도 장황해지지 않는다.
    ("diary_spec('plain')", "max_output_tokens"): (2048, 4096),
    ("diary_spec('emotional')", "max_output_tokens"): (2048, 4096),
    ("diary_spec('workout')", "max_output_tokens"): (2048, 4096),
    ("diary_spec('pet')", "max_output_tokens"): (2048, 4096),
    ("REGISTRY['diary']", "max_output_tokens"): (2048, 4096),
}

# "story" 문체(diary)와 story_image_writer(image)는 분할 전 파일에 존재하지
# 않는 완전히 새로운 항목이라 값 대조 자체가 성립하지 않는다(구조 추가이지
# 값 변경이 아니다). DIARY_STYLES/REGISTRY 키 목록 비교는 이 항목들 때문에
# 계속 FAIL로 남는다 - INTENTIONAL 허용 목록은 스칼라 값 변경만 다루므로
# 여기 넣지 않는다. 새 항목이 늘 때마다 아래 두 라벨의 실패는 예상된 것이다.
NEW_ENTRIES_EXPECTED_TO_FAIL = {"DIARY_STYLES", "REGISTRY 키"}

intentional_seen: set[tuple[str, str]] = set()

failures: list[str] = []
checks = 0


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"불러올 수 없습니다: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def show_text_diff(label: str, old: str, new: str) -> None:
    diff = difflib.unified_diff(
        old.splitlines(keepends=True), new.splitlines(keepends=True),
        fromfile="old", tofile="new", n=1,
    )
    print(f"\n--- {label} 차이 ---")
    for line in list(diff)[:40]:
        print(line.rstrip("\n"))


def compare(label: str, old, new) -> None:
    global checks
    checks += 1
    if old == new:
        return

    key = tuple(label.rsplit(".", 1)) if "." in label else (label, "")
    expected = INTENTIONAL.get(key)
    if expected is not None and (old, new) == expected:
        intentional_seen.add(key)
        print(f"  (의도된 변경) {label}: {old} -> {new}")
        return

    if label in NEW_ENTRIES_EXPECTED_TO_FAIL:
        print(f"  (신규 항목으로 인한 구조 변경, 실패 아님) {label}")
        return

    failures.append(label)
    if isinstance(old, str) and isinstance(new, str):
        show_text_diff(label, old, new)
    else:
        print(f"\n--- {label} 차이 ---")
        print(f"old: {json.dumps(old, ensure_ascii=False, default=str)[:400]}")
        print(f"new: {json.dumps(new, ensure_ascii=False, default=str)[:400]}")


def compare_spec(label: str, old_spec, new_spec) -> None:
    for field in SPEC_FIELDS:
        compare(f"{label}.{field}", getattr(old_spec, field), getattr(new_spec, field))
    # 키 순서까지 본다. 페이로드 바이트를 동일하게 유지해야 diff로 검증할 수 있기 때문이다.
    if old_spec.response_schema is not None:
        compare(
            f"{label}.response_schema(키 순서)",
            json.dumps(old_spec.response_schema, ensure_ascii=False, sort_keys=False),
            json.dumps(new_spec.response_schema, ensure_ascii=False, sort_keys=False),
        )


def main() -> int:
    root = Path(__file__).resolve().parent
    old_path = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "prompts_original.py"
    if not old_path.exists():
        raise SystemExit(f"분할 전 파일을 찾을 수 없습니다: {old_path}")

    old = load_module(old_path, "prompts_original")
    sys.path.insert(0, str(root))
    from walklog import prompts as new

    for name in ("FRAME_EXTRACT", "IMAGE_PROMPT_WRITER",
                 "FLOW_IMAGE_WRITER", "PANEL_CAPTION_WRITER"):
        compare_spec(name, getattr(old, name), getattr(new, name))

    compare("FRAME_SYSTEM", old.FRAME_SYSTEM, new.FRAME_SYSTEM)
    compare("FRAME_SCHEMA", old.FRAME_SCHEMA, new.FRAME_SCHEMA)
    compare("DIARY_STYLES", old.DIARY_STYLES, new.DIARY_STYLES)
    compare("DEFAULT_DIARY_STYLE", old.DEFAULT_DIARY_STYLE, new.DEFAULT_DIARY_STYLE)
    compare("IMAGE_STYLES", old.IMAGE_STYLES, new.IMAGE_STYLES)
    compare("DEFAULT_IMAGE_STYLE", old.DEFAULT_IMAGE_STYLE, new.DEFAULT_IMAGE_STYLE)
    compare("IMAGE_NEGATIVE", old.IMAGE_NEGATIVE, new.IMAGE_NEGATIVE)
    compare("IMAGE_SUFFIX", old.IMAGE_SUFFIX, new.IMAGE_SUFFIX)

    # 모든 문체 프리셋에 대해 실제 조립 결과를 비교한다.
    for style in old.DIARY_STYLES:
        compare_spec(f"diary_spec({style!r})", old.diary_spec(style), new.diary_spec(style))

    # 모든 이미지 스타일에 대해 조립 결과를 비교한다.
    sample = "quiet riverside path at dusk, bare trees, overcast sky,"
    for style in old.IMAGE_STYLES:
        compare(f"build_image_prompt({style!r})",
                old.build_image_prompt(sample, style),
                new.build_image_prompt(sample, style))
    compare("build_image_prompt(extra)",
            old.build_image_prompt(sample, "lineart", extra="wide shot"),
            new.build_image_prompt(sample, "lineart", extra="wide shot"))

    compare("REGISTRY 키", sorted(old.REGISTRY), sorted(new.REGISTRY))
    for key in old.REGISTRY:
        compare_spec(f"REGISTRY[{key!r}]", old.REGISTRY[key], new.REGISTRY[key])

    # PromptSpec 동작 자체
    compare("render()",
            old.FRAME_EXTRACT.render(segment="seg_0000", elapsed="0분 2초",
                                     shot_datetime="불명", location="불명"),
            new.FRAME_EXTRACT.render(segment="seg_0000", elapsed="0분 2초",
                                     shot_datetime="불명", location="불명"))
    compare("tweak().temperature",
            old.FRAME_EXTRACT.tweak(temperature=0.0).temperature,
            new.FRAME_EXTRACT.tweak(temperature=0.0).temperature)

    stale = set(INTENTIONAL) - intentional_seen
    print(f"\n검사 {checks}건, 의도된 변경 {len(intentional_seen)}건, "
          f"불일치 {len(failures)}건")
    if failures:
        for label in failures:
            print(f"  FAIL  {label}")
        return 1
    if stale:
        # 허용 목록에 남아 있지만 실제로는 차이가 없는 항목.
        # 값을 원래대로 되돌렸거나 라벨이 바뀌었다는 뜻이므로 목록을 정리해야 한다.
        print("  경고: 허용 목록에 있으나 실제 차이가 없는 항목이 있습니다:")
        for key in sorted(stale):
            print(f"    - {'.'.join(k for k in key if k)}")
        return 1
    print("의도된 변경 외에는 분할 전후가 완전히 동일합니다.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())