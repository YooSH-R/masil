"""GMSClient 검증. 네트워크 대신 가짜 세션을 꽂는다.

Stage 1(VLM)이 이 프로젝트의 주 경로다. 프레임 수만큼 연속 호출되고,
한 번 실패하면 그 프레임의 관찰 기록이 사라진다. 그래서 이 파일의 무게중심은
"이미지를 붙인 호출과 그 응답 해석"에 있다.
"""

from __future__ import annotations

import base64

import pytest

from walklog import prompts as P
from walklog.gms import (
    GMSAuthError,
    GMSClient,
    GMSEmptyResponse,
    GMSError,
    GMSHTTPError,
    GMSNetworkError,
)

FRAME_VARS = dict(segment="seg_0000", elapsed="1분 30초",
                  shot_datetime="불명", location="불명")


class FakeResponse:
    def __init__(self, payload=None, status=200, text="{}"):
        self._payload = payload if payload is not None else {}
        self.status_code = status
        self.ok = 200 <= status < 300
        self.text = text

    def json(self):
        return self._payload


class FakeSession:
    """post 호출을 기록하고 정해진 응답을 돌려준다."""

    def __init__(self, *responses):
        self.responses = list(responses)
        self.sent: list[dict] = []

    def post(self, url, headers=None, json=None, timeout=None):
        self.sent.append({"url": url, "body": json, "timeout": timeout,
                          "headers": headers})
        return self.responses.pop(0) if self.responses else FakeResponse()

    def close(self):
        pass


def observation(text: str, *, thought: str | None = None,
                finish="STOP", tokens=(1500, 120)):
    """VLM 응답 한 건. thought를 주면 사고 파트를 앞에 붙인다."""
    parts = []
    if thought:
        parts.append({"text": thought, "thought": True})
    parts.append({"text": text})
    return FakeResponse({
        "candidates": [{"content": {"parts": parts}, "finishReason": finish}],
        "usageMetadata": {"promptTokenCount": tokens[0],
                          "candidatesTokenCount": tokens[1],
                          "totalTokenCount": sum(tokens)},
    })


# ------------------------------------------------------------ VLM 요청 조립

def test_image_comes_before_text():
    """이미지가 텍스트보다 앞에 와야 한다.

    user_template의 "위 이미지를 관찰 원칙에 따라 기록하고"가 성립하려면
    이미지가 먼저 들어가야 한다. 순서가 뒤바뀌면 지시가 가리키는 대상이 없어진다.
    """
    session = FakeSession(observation('{"scene":"x"}'))
    client = GMSClient(key="k", session=session)
    client.generate_json(P.FRAME_EXTRACT, images=[("QUJD", "image/jpeg")], **FRAME_VARS)

    parts = session.sent[0]["body"]["contents"][0]["parts"]
    assert "inlineData" in parts[0]
    assert "text" in parts[-1]
    assert "위 이미지" in parts[-1]["text"]


def test_multiple_images_keep_order():
    session = FakeSession(observation('{"scene":"x"}'))
    client = GMSClient(key="k", session=session)
    client.generate_json(
        P.FRAME_EXTRACT,
        images=[("AAAA", "image/jpeg"), ("BBBB", "image/png")],
        **FRAME_VARS,
    )
    parts = session.sent[0]["body"]["contents"][0]["parts"]
    assert [p["inlineData"]["data"] for p in parts[:2]] == ["AAAA", "BBBB"]
    assert parts[1]["inlineData"]["mimeType"] == "image/png"


def test_vlm_uses_text_model_and_short_timeout():
    session = FakeSession(observation('{"scene":"x"}'))
    client = GMSClient(key="k", session=session, text_model="m-vlm", timeout=45)
    client.generate_json(P.FRAME_EXTRACT, images=[("A", "image/jpeg")], **FRAME_VARS)
    assert session.sent[0]["url"].endswith("/models/m-vlm:generateContent")
    assert session.sent[0]["timeout"] == 45


def test_api_key_in_header_not_url():
    session = FakeSession(observation('{"scene":"x"}'))
    client = GMSClient(key="secret-key", session=session)
    client.generate_json(P.FRAME_EXTRACT, images=[("A", "image/jpeg")], **FRAME_VARS)
    assert session.sent[0]["headers"]["x-goog-api-key"] == "secret-key"
    assert "secret-key" not in session.sent[0]["url"]


# ------------------------------------------------------------ 응답 해석

def test_thought_part_is_excluded():
    """사고 파트를 답변으로 착각하면 JSON 파싱이 실패한다.

    분할 전 파이프라인은 첫 text 파트만 꺼냈으므로 사고가 먼저 오면 깨졌고,
    분할 전 삽화 스크립트는 전부 이어붙여 사고를 답변에 섞었다.
    """
    session = FakeSession(observation(
        '{"scene":"젖은 보도블록","unreadable":false}',
        thought="먼저 하늘을 보면 흐린 것 같고...",
    ))
    record = GMSClient(key="k", session=session).generate_json(
        P.FRAME_EXTRACT, images=[("A", "image/jpeg")], **FRAME_VARS)
    assert record == {"scene": "젖은 보도블록", "unreadable": False}


def test_code_fence_is_stripped():
    """프록시가 responseSchema를 거부해 마크다운으로 감싸 오는 경우."""
    session = FakeSession(observation('```json\n{"scene":"공원"}\n```'))
    client = GMSClient(key="k", session=session, use_schema=False)
    assert client.generate_json(P.FRAME_EXTRACT, images=[("A", "image/jpeg")],
                                **FRAME_VARS) == {"scene": "공원"}


def test_token_usage_accumulates():
    session = FakeSession(observation('{"a":1}', tokens=(1000, 100)),
                          observation('{"a":2}', tokens=(900, 80)))
    client = GMSClient(key="k", session=session)
    first = client.generate(P.FRAME_EXTRACT, images=[("A", "image/jpeg")], **FRAME_VARS)
    client.generate(P.FRAME_EXTRACT, images=[("A", "image/jpeg")], **FRAME_VARS)
    assert (first.prompt_tokens, first.output_tokens) == (1000, 100)
    assert client.total_tokens == 1100 + 980


def test_truncated_json_reports_snippet():
    session = FakeSession(observation('{"scene":"공원","objects":["벤'))
    with pytest.raises(GMSError, match="JSON 파싱 실패"):
        GMSClient(key="k", session=session).generate_json(
            P.FRAME_EXTRACT, images=[("A", "image/jpeg")], **FRAME_VARS)


def test_max_tokens_hint():
    """사고 토큰이 출력 예산을 먼저 소진한 경우 힌트를 준다."""
    session = FakeSession(FakeResponse({
        "candidates": [{"content": {"parts": [{"text": "생각만", "thought": True}]},
                        "finishReason": "MAX_TOKENS"}]}))
    with pytest.raises(GMSEmptyResponse, match="max_output_tokens"):
        GMSClient(key="k", session=session).generate_text(
            P.FRAME_EXTRACT, images=[("A", "image/jpeg")], **FRAME_VARS)


def test_max_tokens_with_partial_text_raises():
    """본문이 일부 나왔어도 MAX_TOKENS로 잘렸으면 조용히 반환하지 않는다.

    require_text()가 비어있지 않은 텍스트를 그냥 통과시키면, 사고 토큰이
    본문 도중에 예산을 소진했을 때 잘린 JSON/일지가 에러 없이 저장된다.
    """
    session = FakeSession(observation('{"scene":"공원","objects":[', finish="MAX_TOKENS"))
    with pytest.raises(GMSEmptyResponse, match="잘렸습니다"):
        GMSClient(key="k", session=session).generate_text(
            P.FRAME_EXTRACT, images=[("A", "image/jpeg")], **FRAME_VARS)


def test_blocked_prompt():
    session = FakeSession(FakeResponse({"promptFeedback": {"blockReason": "SAFETY"}}))
    with pytest.raises(GMSEmptyResponse, match="SAFETY"):
        GMSClient(key="k", session=session).generate_json(
            P.FRAME_EXTRACT, images=[("A", "image/jpeg")], **FRAME_VARS)


# ------------------------------------------------------------ 오류 분류

@pytest.mark.parametrize("status,retryable", [
    (400, False),   # 요청이 잘못됨. responseSchema 거부 등. 재시도 무의미
    (404, False),
    (429, True),    # rate limit
    (500, True),
    (503, True),
])
def test_http_error_retryable(status, retryable):
    session = FakeSession(FakeResponse(status=status, text="err"))
    client = GMSClient(key="k", session=session)
    with pytest.raises(GMSHTTPError) as info:
        client.generate_json(P.FRAME_EXTRACT, images=[("A", "image/jpeg")], **FRAME_VARS)
    assert info.value.retryable is retryable
    assert info.value.status == status


def test_auth_error_not_retryable():
    session = FakeSession(FakeResponse(status=401))
    with pytest.raises(GMSAuthError) as info:
        GMSClient(key="k", session=session).generate_json(
            P.FRAME_EXTRACT, images=[("A", "image/jpeg")], **FRAME_VARS)
    assert info.value.retryable is False


def test_network_error_is_retryable():
    import requests

    class Broken(FakeSession):
        def post(self, *a, **kw):
            raise requests.ConnectionError("연결 끊김")

    with pytest.raises(GMSNetworkError) as info:
        GMSClient(key="k", session=Broken()).generate_json(
            P.FRAME_EXTRACT, images=[("A", "image/jpeg")], **FRAME_VARS)
    assert info.value.retryable is True


# ------------------------------------------------------------ 이미지 생성

def test_generate_image_path():
    png = b"\x89PNG-fake"
    session = FakeSession(FakeResponse({
        "candidates": [{"content": {"parts": [
            {"inlineData": {"mimeType": "image/png",
                            "data": base64.b64encode(png).decode()}}]},
            "finishReason": "STOP"}],
        "usageMetadata": {"totalTokenCount": 50}}))
    client = GMSClient(key="k", session=session, image_model="m-img", image_timeout=200)
    prompt = P.build_image_request("quiet riverside path", "watercolor")

    assert client.generate_image(prompt, images=[("A", "image/jpeg")]) == png
    sent = session.sent[0]
    assert sent["url"].endswith("/models/m-img:generateContent")
    assert sent["timeout"] == 200
    assert sent["body"]["generationConfig"] == {"responseModalities": ["IMAGE"]}
    assert "systemInstruction" not in sent["body"]


def test_generate_image_snake_case_response():
    """일부 응답이 inline_data(snake_case)로 오는 경우도 받아들인다."""
    png = b"png"
    session = FakeSession(FakeResponse({
        "candidates": [{"content": {"parts": [
            {"inline_data": {"mime_type": "image/png",
                             "data": base64.b64encode(png).decode()}}]}}]}))
    assert GMSClient(key="k", session=session).generate_image("p") == png


def test_missing_image_part():
    session = FakeSession(observation("여기 그림 설명입니다"))
    with pytest.raises(GMSEmptyResponse, match="responseModalities"):
        GMSClient(key="k", session=session).generate_image("p")


# ------------------------------------------------------------ 설정 경계

def test_client_construction_needs_no_key(monkeypatch):
    """생성만으로는 키를 요구하지 않아야 한다. 그래야 가짜 세션 테스트가 가능하다."""
    monkeypatch.delenv("GMS_KEY", raising=False)
    monkeypatch.setattr("walklog.config._env_loaded", True)
    client = GMSClient(session=FakeSession())
    assert client.total_tokens == 0


def test_merge_mode_moves_system_into_user():
    session = FakeSession(observation('{"scene":"x"}'))
    client = GMSClient(key="k", session=session, system_mode="merge")
    client.generate_json(P.FRAME_EXTRACT, images=[("A", "image/jpeg")], **FRAME_VARS)

    body = session.sent[0]["body"]
    assert "systemInstruction" not in body
    text = body["contents"][0]["parts"][-1]["text"]
    assert "산책 관찰 기록원" in text and "위 이미지" in text