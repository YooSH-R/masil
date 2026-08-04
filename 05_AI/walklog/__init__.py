"""산책 일지 파이프라인.

의존은 아래로만 흐른다:
    cli -> stages -> (prompts, gms, records) -> config
prompts는 아무것도 import하지 않는다.

이 파일은 의도적으로 비워 둔다. 여기서 하위 모듈을 import하면
`from walklog import prompts` 한 줄이 config와 gms까지 끌고 오면서
requests/cv2 의존과 API 키 요구가 되살아난다.
"""

__version__ = "0.1.0"