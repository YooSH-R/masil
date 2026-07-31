# 05_AI — 산책 일지 / 산책 흐름 삽화 생성

산책 중 촬영된 영상에서 뽑은 프레임(사진) 로그를 입력으로,

1. 멀티모달 VLM으로 각 프레임을 관찰·기록하고
2. 그 기록을 엮어 산책 일지(글)를 쓰고
3. 대표 장면을 골라 새로운 그림체의 삽화로 재생성한다.

Gemini 계열 모델을 SSAFY GMS 프록시로 호출한다.

## 파이프라인

```
프레임 폴더 (data/sample_image, manifest.json)
        │
        ▼
[Stage 0] 표본 추출 (로컬, API 없음)
  시간순 프레임을 N등분 → 등분마다 무작위 1장
        │
        ▼
[Stage 1] 관찰 기록 (VLM)               run_walk_log.py
  표본 프레임 각각을 구조화 JSON으로 기록
        │
        ▼
[Stage 2] 산책 일지 (LLM)               run_walk_log.py
  관찰 기록을 자연어 일지 한 편으로 엮음
        │
        ▼
[Stage 3] 장면 선정 → 프롬프트 → 삽화 → 스토리보드   run_flow_image.py
  A. 장면 전환 감지, 대표 프레임 선정 (로컬)
  B. 장면별 영어 이미지 프롬프트 작성 (LLM)
  C. 원본 프레임을 참조한 image-to-image 삽화 생성 (이미지 모델)
  D. 삽화들을 스토리보드 한 장으로 합성 (로컬, Pillow)
```

각 단계는 `walklog/stages/observe.py`(Stage 1), `compose.py`(Stage 2),
`illustrate.py`(Stage 3)에 분리되어 있고, 두 CLI(`run_walk_log.py`,
`run_flow_image.py`)가 이들을 조립한다.

### Stage 0 — 표본 추출을 앞단에 둔 이유

VLM 호출(Stage 1)은 장당 과금된다. 추출된 프레임 전부를 설명하면 장수가
늘어날수록 비용과 실행 시간이 그대로 늘어난다. 그래서 **VLM을 부르기 전에**
시간순 프레임 목록을 N등분(기본 4등분)하고, 등분마다 무작위로 1장씩만 뽑아
그 프레임에만 VLM을 호출한다 (`walklog/records.py`의 `sample_time_quantiles`).

- 등분 경계를 고정하지 않고 등분 **안에서 무작위로** 고르는 이유: 정확히
  25%, 50% 지점처럼 고정하면 매번 같은 순간만 보게 되어, 하필 그 프레임이
  흐리거나 사람이 시야를 가리고 있어도 대안이 없다. 등분 안에서 무작위로
  고르면 같은 시간대를 대표하면서도 매번 다른 프레임을 시도할 여지가 남는다.
- 등분이 이미 시간순 연속 구간이므로 뽑힌 결과도 자동으로 시간순이다.
- 장면 선정(Stage 3A)이 관찰 결과가 나온 **뒤에** 대표 프레임을 고르는 것과
  섞지 않는다. 그건 이미 전부 VLM을 태운 뒤라 비용을 아낄 수 없다. 표본
  추출은 반드시 Stage 1 이전, 파일 메타데이터만 가지고 이뤄진다.

## 디렉토리 구조

```
05_AI/
├── run_walk_log.py         # CLI 진입점: Stage 0~2
├── run_flow_image.py       # CLI 진입점: Stage 3
├── walklog/
│   ├── config.py           # API 주소, 모델명, 크기 제한 등 모든 상수
│   ├── records.py          # 프레임 탐색, 표본 추출, 관찰 기록 자료구조/저장
│   ├── diagnostics.py      # 프록시 호환성 진단 (--check)
│   ├── gms/                # GMS(Gemini) 호출 클라이언트, 요청 조립, 이미지 인코딩
│   ├── prompts/             # 단계별 프롬프트 (frame/diary/image), 스타일 프리셋
│   ├── stages/              # observe(Stage1) / compose(Stage2) / illustrate(Stage3)
│   └── cli/                 # 두 CLI의 실제 argparse + main 로직
├── data/sample_image/       # 샘플 프레임 + manifest.json
├── outputs/<날짜>/          # 실행 결과 (frame_records.json, walk_log.md, 삽화 등)
├── tests/                   # pytest 테스트
└── docs/프롬프트_전략.md    # 프롬프트 설계 메모
```

## 준비

```bash
pip install -r requirements.txt
cp .env.sample .env      # GMS_KEY 값을 채운다
```

```bash
python run_walk_log.py --check   # 프록시가 systemInstruction/responseSchema를
                                  # 지원하는지 진단만 하고 종료
```

## 사용법

### Stage 0~2: 관찰 기록 + 일지

```bash
python run_walk_log.py                              # 기본: 4등분 표본, 4장만 VLM 호출
python run_walk_log.py --quarters 6                  # 6등분 → 6장만 VLM 호출
python run_walk_log.py --no-sample                   # 표본 추출 없이 전체 프레임 처리
python run_walk_log.py --sample-seed 42               # 표본 추출 결과를 재현 가능하게 고정
python run_walk_log.py --style emotional              # 일지 문체 변경 (plain/emotional/workout/pet)
python run_walk_log.py --started-at 2026-07-28T08:12:03   # 촬영 일시 기반 시간대 추정
python run_walk_log.py --limit 2 --dump-payload       # 앞 2장만, 실제 요청을 payload/에 덤프
python run_walk_log.py --records outputs/2026-07-28/frame_records.json --no-observe
                                                       # Stage 1 재호출 없이 저장된 기록으로 일지만 다시 작성
```

결과는 `outputs/<날짜>/`에 쌓인다: `frame_records.json`(관찰 기록), `walk_log.md`(일지).

### Stage 3: 산책 흐름 삽화

```bash
python run_flow_image.py --dry-run              # API 호출 없이 장면 선정 결과만 확인
python run_flow_image.py -n 5 --style watercolor # 대표 장면 5개, 수채화 스타일
python run_flow_image.py --mode single           # 산책 전체를 한 장으로 요약
python run_flow_image.py --no-ref --layout grid  # 원본 프레임 참조 없이, 격자 배치
```

이미지 스타일 프리셋: `watercolor`(기본), `storybook`, `lineart`, `photoreal`, `pixel`
(`walklog/prompts/image.py`에서 추가/수정).

결과는 `outputs/<날짜>/walk_flow.png`(스토리보드)와 `flow_panels/`(칸별 원본 삽화)에 쌓인다.

## 테스트

```bash
python -m pytest tests/ -q
```
