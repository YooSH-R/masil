"""GMS 프록시를 경유한 Gemini 호출.

[분할 전 상태]
호출부가 두 개였고 각자 상대방의 기능을 빠뜨렸다.
  walk_log_pipeline.run  : examples / merge 모드 / responseSchema 지원.
                           세션 미사용. 첫 text 파트만 꺼냄.
  generate_flow_image.Gms: 세션 재사용. 이미지 생성 지원.
                           examples / merge / responseSchema 전부 무시.
                           인증 실패 시 라이브러리 층에서 sys.exit 호출.
이 클래스는 둘의 합집합이며, 아래 네 가지를 바로잡았다.

[바로잡은 것]
1. thought 파트 제외. thinking 모델은 사고 내용을 "thought": true 가 붙은
   별도 파트로 돌려준다. 첫 파트만 꺼내면 사고를 답변으로 착각해 JSON 파싱이
   실패하고, 전부 이어붙이면 사고가 답변에 섞인다. 둘 다 틀렸다.
2. sys.exit 대신 예외. 프로세스를 죽일지는 CLI가 판단한다. 그래야
   "프레임 하나 실패로 전체가 멈추지 않는다"는 기존 동작이 유지된다.
3. system_mode / use_schema를 모듈 전역이 아니라 생성자 인자로 받는다.
   진단 코드가 전역을 건드리지 않고 다른 모드의 클라이언트를 만들 수 있다.
4. 토큰 사용량을 print하지 않고 GenResult로 반환한다. 출력은 CLI의 일이다.
"""

from __future__ import annotations

import base64
import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Sequence

import requests

from .. import config
from ..prompts import PromptSpec
from . import payload as payload_mod
from .imaging import encode_image
from .payload import InlineImage

__all__ = [
    "GMSError",
    "GMSAuthError",
    "GMSNetworkError",
    "GMSHTTPError",
    "GMSEmptyResponse",
    "GenResult",
    "GMSClient",
    "strip_code_fence",
]


class GMSError(RuntimeError):
    """GMS 호출 실패의 최상위 예외.

    retryable 은 "다시 보내면 성공할 수도 있는가"다.
    Stage 1은 프레임 수만큼 연속 호출하므로 일시적 실패 한 번에
    프레임이 버려지지 않도록 호출부가 이 값으로 판단한다.
    """

    retryable = False


class GMSAuthError(GMSError):
    """인증 실패(401/403). 키를 확인해야 한다. 재시도해도 같은 결과다."""

    retryable = False


class GMSNetworkError(GMSError):
    """연결 실패/타임아웃. 대표적인 재시도 대상이다."""

    retryable = True


class GMSHTTPError(GMSError):
    """그 외 HTTP 실패."""

    def __init__(self, status: int, body: str, model: str):
        super().__init__(f"{model} HTTP {status}\n{body}")
        self.status = status
        self.body = body
        self.model = model

    @property
    def retryable(self) -> bool:
        """429(rate limit)와 5xx(서버 측)는 다시 보내면 될 수 있다.

        400은 요청 자체가 잘못된 것이므로 재시도가 무의미하다.
        responseSchema나 thinkingConfig를 프록시가 거부하는 경우가 여기 해당한다.
        """
        return self.status == 429 or 500 <= self.status < 600


class GMSEmptyResponse(GMSError):
    """응답에 쓸 수 있는 파트가 없다. 안전 차단, 토큰 소진 등.

    같은 요청을 다시 보내도 대개 같은 결과다. 프롬프트나
    max_output_tokens / thinking_budget 을 손봐야 한다.
    """

    retryable = False


_FENCE_RE = re.compile(r"^```(?:json)?|```$", re.MULTILINE)


def strip_code_fence(text: str) -> str:
    """responseSchema 미사용 시에도 파싱되도록 코드펜스를 걷어낸다."""
    return _FENCE_RE.sub("", text.strip()).strip()


@dataclass(frozen=True)
class GenResult:
    """한 번의 호출 결과.

    텍스트와 이미지를 함께 담는다. 이미지 모델은 텍스트가 아니라 inlineData
    바이트를 돌려주므로, 반환형을 str로 못 박으면 삽화 경로가 클라이언트
    밖으로 새어 나간다.
    """

    text: str
    images: list[bytes] = field(default_factory=list)
    usage: dict[str, Any] = field(default_factory=dict)
    finish_reason: str | None = None
    raw: dict[str, Any] = field(default_factory=dict)

    @property
    def total_tokens(self) -> int:
        return int(self.usage.get("totalTokenCount") or 0)

    @property
    def prompt_tokens(self) -> int:
        return int(self.usage.get("promptTokenCount") or 0)

    @property
    def output_tokens(self) -> int:
        return int(self.usage.get("candidatesTokenCount") or 0)

    def require_text(self) -> str:
        if not self.text:
            hint = ""
            if self.finish_reason == "MAX_TOKENS":
                hint = " (max_output_tokens를 늘려 보세요. 사고 토큰이 먼저 소진됐을 수 있습니다)"
            raise GMSEmptyResponse(
                f"응답에 텍스트가 없습니다 (finishReason={self.finish_reason}){hint}"
            )
        
        if self.finish_reason == "MAX_TOKENS":
            raise GMSEmptyResponse(
                f"응답이 토큰 한도에서 잘렸습니다 (출력 {self.output_tokens}토큰). "
                "max_output_tokens를 늘리거나 thinking_budget을 제한하세요. "
                f"잘린 앞부분: {self.text[:80]!r}"
            )
        return self.text

    def require_image(self) -> bytes:
        if not self.images:
            raise GMSEmptyResponse(
                "응답에 이미지 파트가 없습니다. "
                "responseModalities 지원 여부를 확인하세요. "
                f"(finishReason={self.finish_reason}, "
                f"텍스트={self.text[:80]!r})"
            )
        return self.images[0]

    def as_json(self) -> dict[str, Any]:
        text = self.require_text()
        cleaned = strip_code_fence(text)
        try:
            return json.loads(cleaned)
        except json.JSONDecodeError as exc:
            raise GMSError(
                f"JSON 파싱 실패: {exc}\n응답 앞부분: {cleaned[:200]!r}"
            ) from exc


class GMSClient:
    """GMS 프록시 클라이언트.

    세션을 재사용한다. 프레임 11장을 연속 처리할 때 TLS 핸드셰이크가
    한 번으로 줄어든다(분할 전 파이프라인은 매번 새로 열었다).
    """

    def __init__(
        self,
        *,
        key: str | None = None,
        base: str = config.BASE,
        text_model: str = config.TEXT_MODEL,
        image_model: str = config.IMAGE_MODEL,
        system_mode: str = config.SYSTEM_MODE,
        use_schema: bool = config.USE_RESPONSE_SCHEMA,
        timeout: int = config.REQUEST_TIMEOUT,
        image_timeout: int = config.IMAGE_TIMEOUT,
        session: requests.Session | None = None,
        dump_dir: str | Path | None = None,
    ):
        self._key = key
        self.base = base.rstrip("/")
        self.text_model = text_model
        self.image_model = image_model
        self.system_mode = config.check_system_mode(system_mode)
        self.use_schema = use_schema
        self.timeout = timeout
        self.image_timeout = image_timeout
        self.session = session or requests.Session()
        self.dump_dir = Path(dump_dir) if dump_dir else None
        self.total_tokens = 0
        self._dump_seq = 0

    # -------------------------------------------------- 내부

    def _auth_key(self) -> str:
        """키를 실제 호출 시점에 해석한다.

        생성자에서 config.get_key()를 부르면 클라이언트를 만드는 것만으로
        키가 필요해진다. 가짜 세션을 꽂아 테스트할 수 없게 된다.
        """
        return self._key or config.get_key()

    def _dump(self, tag: str, body: dict[str, Any]) -> None:
        if self.dump_dir is None:
            return
        self.dump_dir.mkdir(parents=True, exist_ok=True)
        self._dump_seq += 1
        safe = re.sub(r"[^A-Za-z0-9_.-]", "_", tag)
        out = self.dump_dir / f"{self._dump_seq:03d}_{safe}.json"
        # 이미지 base64는 지문으로 치환해 저장한다. 원본이면 diff가 무의미해진다.
        out.write_text(
            json.dumps(payload_mod.fingerprint_payload(body),
                       ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    def _post(self, model: str, body: dict[str, Any], timeout: int, tag: str) -> dict[str, Any]:
        self._dump(tag, body)
        try:
            res = self.session.post(
                f"{self.base}/models/{model}:generateContent",
                headers={"Content-Type": "application/json",
                         "x-goog-api-key": self._auth_key()},
                json=body,
                timeout=timeout,
            )
        except requests.RequestException as exc:
            raise GMSNetworkError(f"{model} 요청 실패: {exc}") from exc

        if res.status_code in (401, 403):
            raise GMSAuthError(
                f"인증 실패({res.status_code}). {config.KEY_ENV} 를 확인하세요."
            )
        if not res.ok:
            raise GMSHTTPError(res.status_code, res.text[:500], model)

        try:
            data = res.json()
        except ValueError as exc:
            raise GMSError(f"{model} 응답이 JSON이 아닙니다: {res.text[:200]!r}") from exc

        self.total_tokens += int((data.get("usageMetadata") or {}).get("totalTokenCount") or 0)
        return data

    @staticmethod
    def _extract(data: dict[str, Any]) -> GenResult:
        candidates = data.get("candidates") or []
        if not candidates:
            feedback = data.get("promptFeedback") or {}
            reason = feedback.get("blockReason") or "알 수 없음"
            raise GMSEmptyResponse(f"응답에 candidates가 없습니다 (사유: {reason})")

        candidate = candidates[0]
        parts = (candidate.get("content") or {}).get("parts") or []

        texts: list[str] = []
        images: list[bytes] = []
        for part in parts:
            # thinking 모델의 사고 파트. 답변이 아니므로 제외한다.
            if part.get("thought"):
                continue
            text = part.get("text")
            if text:
                texts.append(text)
            blob = part.get("inlineData") or part.get("inline_data")
            if isinstance(blob, dict) and blob.get("data"):
                images.append(base64.b64decode(blob["data"]))

        return GenResult(
            text="".join(texts).strip(),
            images=images,
            usage=data.get("usageMetadata") or {},
            finish_reason=candidate.get("finishReason"),
            raw=data,
        )

    def _load_images(
        self, images: Sequence[tuple[str, str]], image_paths: Sequence[str | Path],
    ) -> list[InlineImage]:
        loaded = [InlineImage(*img) for img in images]
        loaded.extend(encode_image(p) for p in image_paths)
        return loaded

    # -------------------------------------------------- 공개

    def generate(
        self,
        spec: PromptSpec,
        *,
        image_paths: Sequence[str | Path] = (),
        images: Sequence[tuple[str, str]] = (),
        model: str | None = None,
        timeout: int | None = None,
        tag: str | None = None,
        **vars: Any,
    ) -> GenResult:
        """PromptSpec 하나를 실행한다.

        image_paths를 주면 여기서 인코딩한다. 이미 인코딩된 것이 있으면 images로 넘긴다.
        (테스트는 images에 고정값을 넣어 인코더를 변수에서 제거한다)
        """
        body = payload_mod.payload_from_spec(
            spec,
            images=self._load_images(images, image_paths),
            system_mode=self.system_mode,
            use_schema=self.use_schema,
            **vars,
        )
        data = self._post(
            model or self.text_model,
            body,
            timeout if timeout is not None else self.timeout,
            tag or "text",
        )
        return self._extract(data)

    def generate_text(self, spec: PromptSpec, **kwargs: Any) -> str:
        """텍스트를 반환한다. 없으면 예외. Stage 2(일지), Stage 3B(영어 프롬프트)용."""
        return self.generate(spec, **kwargs).require_text()

    def generate_json(self, spec: PromptSpec, **kwargs: Any) -> dict[str, Any]:
        """JSON 응답을 dict로 반환한다. Stage 1(관찰 기록)의 주 경로다.

        코드펜스가 붙어 있어도 파싱한다(responseSchema를 못 쓰는 프록시 대비).
        """
        return self.generate(spec, **kwargs).as_json()

    def generate_image(
        self,
        prompt: str,
        *,
        reference: str | Path | None = None,
        images: Sequence[tuple[str, str]] = (),
        model: str | None = None,
        timeout: int | None = None,
        tag: str | None = None,
    ) -> bytes:
        """이미지를 생성해 바이트로 반환한다.

        prompt는 prompts.build_image_request()가 만든 완성된 문자열이다.
        PromptSpec을 받지 않는 이유: 이미지 호출에는 시스템 프롬프트도
        스키마도 없고 responseModalities만 필요하다. 스펙 껍데기를 씌우면
        없는 개념을 억지로 끼우는 셈이 되고, render()의 .format()이
        프롬프트 안의 중괄호를 터뜨린다.

        reference를 주면 실제 프레임을 참조하는 image-to-image가 된다.
        """
        loaded = self._load_images(images, [reference] if reference else [])
        body = payload_mod.build_payload(
            user_text=prompt,
            images=loaded,
            generation_config=dict(payload_mod.IMAGE_GENERATION_CONFIG),
        )
        data = self._post(
            model or self.image_model,
            body,
            timeout if timeout is not None else self.image_timeout,
            tag or "image",
        )
        return self._extract(data).require_image()

    # -------------------------------------------------- 자원 정리

    def close(self) -> None:
        self.session.close()

    def __enter__(self) -> "GMSClient":
        return self

    def __exit__(self, *exc_info: Any) -> None:
        self.close()