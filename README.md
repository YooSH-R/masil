# A203 AIoT 프로젝트
## 주제: AIoT - Jetson Orin Nano를 활용한 산책 일지 작성 반려봇

## ☀️ Morning Routine
```
git fetch
git switch dev
git pull origin dev
git switch [본인 작업 브랜치]
git merge dev

# 충돌 발생 시:
#   1. 충돌 파일 수정
#   2. git add <파일>
#   3. git commit
```

## Commit Convention
| Type | 설명 |
| --- | --- |
| `✨ Feat` | `새로운 기능 추가` |
| `🐛 Fix` | `버그 수정` |
| `📝 Docs` | `문서 수정` |
| `⚡️ Style` | `코드 포맷팅, 세미콜론 수정, 코드 변경 없음` |
| `♻️ Refactor` | `코드 리팩토링` |
| `🧪 Test` | `테스트 코드 추가/수정` |
| `🏗️ Chore` | `빌드, 패키지, 설정 등 기타 변경` |
| `🎨 Design` | `UI, CSS 변경` |
| `💡 Comment` | `주석 추가 및 수정` |
| `✅ Init` | `프로젝트 초기 생성` |
| `🚚 Rename` | `파일 또는 폴더 이름 변경` |
| `🔥 Remove` | `파일 삭제` |

#### Tip
[![Gitmoji](https://img.shields.io/badge/gitmoji-%20😜%20😍-FFDD67.svg?style=for-the-badge)](https://gitmoji.dev/) 설치 가이드
```
1. node js 설치
2. node -v / npm -v 로 버전 확인
3. npm i -g gitmoji-cli 로 깃모지 설치
4. gitmoji -c 로 깃모지 활용 (커밋메시지 편하게 남기기)
```

## Branch Guide
  ![gitflow](./00_sub1/SeongHyun%20Kim/gitflow_img.png)
```
master Branch (Main Release Branch)
  ↑
  ├─ Merge(Pull) Request (Tested & Ready)
  │
dev Branch(Development Integration Branch)
  ↑
  ├─ Merge(Pull) Request
  │
Feature Branches - Role-based
  ├─ feat/FE/Web_Dashboard
  ├─ feat/BE/DB_ERD
  ├─ feat/EMB/Camera_Setting
  ├─ feat/AI/Model_Training
  ├─ feat/Infra/Docker_Setup
  └─ feat/Docs/README
  ```

## Branch Control
```
온라인 git 현황 최신화
git fetch

현재 "로컬" 브랜치 확인
git branch

새로운 브랜치 생성
git switch -b [브랜치 명]

브랜치 이동
git switch [이동 할 브랜치 명]

작업 현황 임시 저장
git stash

변경사항 저장
git add . (점 하나면 변경한 작업물 모두)

커밋 메시지 남기기
git commit -m "[커밋 메시지 제목]" -m "[커밋 메시지 본문]"
or
git commit (편집기에서 작성)
or
gitmoji -c

원격 저장소에 변경사항 업로드
git push origin [브랜치 명]
```
---
### 협업 툴
[![Notion](https://img.shields.io/badge/Notion-000000?style=for-the-badge&logo=notion&logoColor=white)](https://app.notion.com/p/SSAFY-15-39c5283b0f4a8015b8a3fa2a71acea02?source=copy_link)
[![Jira](https://img.shields.io/badge/Jira-0052CC?style=for-the-badge&logo=jira&logoColor=white)](https://ssafy.atlassian.net/jira/software/c/projects/S15P11A203/boards/14225)