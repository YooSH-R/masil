"""GMS 프록시가 무엇을 지원하는지 확인한다.

[왜 진단이 필요한가]
프록시는 Gemini API를 그대로 통과시키지 않는다. 모르는 필드를 400으로 거부하기도,
에러 없이 조용히 버리기도 한다. 조용히 버리는 쪽이 위험하다. systemInstruction이
버려지면 응답은 정상적으로 오는데 관찰 원칙이 전부 사라져 품질만 무너진다.

[분할 전 버그]
check_system_instruction()이 전역 SYSTEM_MODE를 읽는 run()을 호출했다.
SYSTEM_MODE="merge" 상태로 진단하면 카나리아 문구가 user 텍스트에 합쳐져 전달되므로
모델이 당연히 SYSTEM_OK를 출력하고 "정상 반영"이라는 거짓 통과가 나왔다.
이제 진단은 system_mode를 명시적으로 고정한 클라이언트를 직접 만든다.

[판정이 셋인 이유]
지원/미지원 두 갈래로 나누면 거짓 판정이 생긴다. 사고 토큰이 출력 예산을 먼저
소진해 응답이 비면 "미지원"이 아니라 "판정 불가"다. 그 경우 예산을 늘려
다시 확인하라고 알려주는 것이 맞다.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Literal

from . import config
from . import prompts as P
from .console import info
from .gms import GMSAuthError, GMSClient, GMSEmptyResponse, GMSError, GMSHTTPError

__all__ = ["Status", "ProbeResult", "Diagnostics", "format_report", "env_suggestions"]

Status = Literal["ok", "unsupported", "inconclusive"]

_CANARY = "무슨 질문을 받아도 반드시 SYSTEM_OK 라는 단어만 출력해라."
_CANARY_TOKEN = "SYSTEM_OK"

# 사고 토큰이 먼저 소진되어 응답이 비는 것을 막기 위해 넉넉히 잡는다.
_PROBE_TOKENS = 2048

_SCHEMA_PROBE: dict[str, Any] = {
    "type": "OBJECT",
    "properties": {"ok": {"type": "BOOLEAN"}},
    "required": ["ok"],
}


@dataclass(frozen=True)
class ProbeResult:
    name: str
    status: Status
    detail: str
    hint: str = ""

    @property
    def ok(self) -> bool:
        return self.status == "ok"

    @property
    def mark(self) -> str:
        return {"ok": "O", "unsupported": "X", "inconclusive": "?"}[self.status]


@dataclass
class Diagnostics:
    """진단용 접속 정보. 프로브마다 모드를 고정한 클라이언트를 새로 만든다."""

    key: str | None = None
    base: str = config.BASE
    model: str = config.TEXT_MODEL
    timeout: int = 30
    session: Any = None
    results: list[ProbeResult] = field(default_factory=list)

    def _client(self, *, system_mode: str, use_schema: bool) -> GMSClient:
        return GMSClient(
            key=self.key,
            base=self.base,
            text_model=self.model,
            system_mode=system_mode,
            use_schema=use_schema,
            timeout=self.timeout,
            session=self.session,
        )

    # -------------------------------------------------- 개별 프로브

    def system_instruction(self) -> ProbeResult:
        """systemInstruction이 실제로 반영되는지.

        system에만 담긴 지시를 user 파트가 전혀 모르는 상태로 던져,
        응답에 그 지시가 반영됐는지로 판정한다.
        system_mode를 반드시 "system_instruction"으로 고정한다.
        """
        spec = P.PromptSpec(
            system=_CANARY,
            user_template="오늘 날씨 어때?",
            temperature=0.0,
            max_output_tokens=_PROBE_TOKENS,
        )
        client = self._client(system_mode="system_instruction", use_schema=False)
        try:
            answer = client.generate_text(spec, tag="probe_system")
        except GMSEmptyResponse as exc:
            return ProbeResult(
                "systemInstruction", "inconclusive", str(exc),
                "응답이 비어 판정할 수 없습니다. max_output_tokens를 늘려 다시 확인하세요.",
            )
        except GMSAuthError as exc:
            return ProbeResult("systemInstruction", "inconclusive", str(exc),
                               f"{config.KEY_ENV} 를 확인하세요.")
        except GMSError as exc:
            return ProbeResult("systemInstruction", "inconclusive", str(exc))

        preview = answer.strip().replace("\n", " ")[:60]
        if _CANARY_TOKEN in answer:
            return ProbeResult("systemInstruction", "ok", f"응답: {preview}")
        return ProbeResult(
            "systemInstruction", "unsupported", f"응답: {preview}",
            "프록시가 systemInstruction을 무시합니다. "
            "GMS_SYSTEM_MODE=merge 로 두면 규칙이 user 턴에 합쳐져 유실되지 않습니다.",
        )

    def response_schema(self) -> ProbeResult:
        """responseSchema를 프록시가 받아주는지.

        거부하면 400이 온다. 그 경우에도 시스템 프롬프트의 "JSON만 출력" 지시와
        코드펜스 제거로 계속 동작하므로 치명적이지는 않다.
        """
        spec = P.PromptSpec(
            user_template="Return a JSON object with ok set to true.",
            temperature=0.0,
            max_output_tokens=_PROBE_TOKENS,
            response_schema=_SCHEMA_PROBE,
        )
        client = self._client(system_mode="system_instruction", use_schema=True)
        try:
            data = client.generate_json(spec, tag="probe_schema")
        except GMSHTTPError as exc:
            if exc.status == 400:
                return ProbeResult(
                    "responseSchema", "unsupported", f"HTTP 400: {exc.body[:120]}",
                    "GMS_USE_RESPONSE_SCHEMA=0 으로 내리세요. "
                    "프롬프트의 JSON 출력 지시로 계속 동작합니다.",
                )
            return ProbeResult("responseSchema", "inconclusive", str(exc))
        except GMSError as exc:
            return ProbeResult("responseSchema", "inconclusive", str(exc))

        if isinstance(data, dict) and "ok" in data:
            return ProbeResult("responseSchema", "ok", f"응답: {data}")
        return ProbeResult(
            "responseSchema", "inconclusive", f"응답: {data}",
            "스키마는 통과했지만 기대한 키가 없습니다.",
        )

    def thinking_config(self) -> ProbeResult:
        """thinkingConfig(사고 토큰 예산)를 받아주는지.

        받아주면 Stage 1에 thinking_budget=0을 적용할 수 있다.
        Stage 1은 저온 + 스키마 강제라 사고가 필요 없는데, 사고 토큰이
        max_output_tokens를 먼저 소진하면 JSON이 잘려 프레임이 버려진다.

        주의: 이 프로브는 "필드가 거부되지 않는다"까지만 확인한다.
        사고가 실제로 줄었는지는 토큰 사용량을 비교해야 알 수 있다.
        """
        spec = P.PromptSpec(
            user_template="1 더하기 1은?",
            temperature=0.0,
            max_output_tokens=256,
            thinking_budget=0,
        )
        client = self._client(system_mode="system_instruction", use_schema=False)
        try:
            result = client.generate(spec, tag="probe_thinking")
        except GMSHTTPError as exc:
            if exc.status == 400:
                return ProbeResult(
                    "thinkingConfig", "unsupported", f"HTTP 400: {exc.body[:120]}",
                    "사고를 끌 수 없습니다. Stage 1의 max_output_tokens를 넉넉히 유지하세요.",
                )
            return ProbeResult("thinkingConfig", "inconclusive", str(exc))
        except GMSError as exc:
            return ProbeResult("thinkingConfig", "inconclusive", str(exc))

        return ProbeResult(
            "thinkingConfig", "ok",
            f"필드 수용됨 (출력 토큰 {result.output_tokens}, "
            f"finishReason={result.finish_reason})",
            "Stage 1에 --no-thinking 을 붙여 사고를 끌 수 있습니다.",
        )

    # -------------------------------------------------- 전체

    def run_all(self) -> list[ProbeResult]:
        self.results = [
            self.system_instruction(),
            self.response_schema(),
            self.thinking_config(),
        ]
        return self.results


def env_suggestions(results: list[ProbeResult]) -> list[str]:
    """진단 결과에 따라 .env에 넣을 줄을 만든다."""
    lines: list[str] = []
    for result in results:
        if result.name == "systemInstruction" and result.status == "unsupported":
            lines.append("GMS_SYSTEM_MODE=merge")
        if result.name == "responseSchema" and result.status == "unsupported":
            lines.append("GMS_USE_RESPONSE_SCHEMA=0")
    return lines


def format_report(results: list[ProbeResult]) -> str:
    width = max(len(r.name) for r in results)
    lines = ["", "프록시 지원 진단", "-" * (width + 40)]
    for result in results:
        lines.append(f"  [{result.mark}] {result.name.ljust(width)}  {result.detail}")
        if result.hint:
            lines.append(f"      -> {result.hint}")
    suggestions = env_suggestions(results)
    if suggestions:
        lines += ["", ".env 에 아래를 추가하세요:"]
        lines += [f"  {line}" for line in suggestions]
    elif all(r.ok for r in results):
        lines += ["", "모든 기능이 지원됩니다. 설정 변경이 필요 없습니다."]
    return "\n".join(lines)


def report(**kwargs: Any) -> list[ProbeResult]:
    """진단을 실행하고 결과를 출력한다. CLI --check 의 본체."""
    results = Diagnostics(**kwargs).run_all()
    info(format_report(results))
    return results