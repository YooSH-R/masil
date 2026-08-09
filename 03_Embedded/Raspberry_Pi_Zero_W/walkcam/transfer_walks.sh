#!/bin/bash
# =============================================================
# transfer_walks.sh — 산책 영상 자동 전송 (파이 제로 → Jetson)
# 위치: /home/piw/transfer_walks.sh  (chmod +x 필수)
# usb0이 올라오면 dispatcher가 이 스크립트를 실행한다.
#
# [2026-08-06 변경] 세션 전송 성공 직후 Jetson 쪽 세션 폴더에
# TRANSFER_DONE 마커를 만든다. Jetson의 walklog-watch.path
# (PathExistsGlob)가 이 파일의 등장을 감지해 AI 파이프라인을
# 실행한다. 즉 이 마커가 "모든 파일이 도착했다"는 신호이며,
# 반드시 rsync 성공 뒤에만 만들어야 한다 — 전송 중간에 만들면
# Jetson이 반쪽짜리 세션을 처리하게 된다.
# =============================================================

set -u

# ---------- 설정 ----------
SRC_DIR="/home/piw/walk"
DST_USER="jetson"
DST_HOST="192.168.7.1"
DST_DIR="~/video2image/video"
MARKER="session.json"              # 녹화 완료 마커 (없는 세션은 전송 제외)
DONE_MARKER="TRANSFER_DONE"        # 전송 완료 마커 (Jetson 파이프라인 트리거)
LOG="/home/piw/walk-transfer.log"
LOCK="/tmp/walk-transfer.lock"
MAX_RETRY=30                       # 세션당 최대 재시도 횟수
RETRY_WAIT=10                      # 재시도 간격(초)
MIN_FREE_MB=1024                   # Jetson 최소 여유 공간(MB)
DELETE_AFTER_VERIFY=0              # 1이면 검증 후 파이 쪽 세션 삭제

log() { echo "[$(date '+%F %T')] $*" >> "$LOG"; }

# ---------- 중복 실행 방지 ----------
# 링크 플래핑으로 up 이벤트가 연달아 와도 인스턴스는 하나만.
exec 9>"$LOCK"
if ! flock -n 9; then
    log "이미 전송 중 — 새 인스턴스 종료"
    exit 0
fi

log "===== 전송 세션 시작 ====="

# ---------- Jetson 응답 대기 ----------
# usb0 up 직후엔 상대편 준비가 안 됐을 수 있으므로 최대 30초 대기
for i in $(seq 1 30); do
    ping -c1 -W1 "$DST_HOST" >/dev/null 2>&1 && break
    sleep 1
done
if ! ping -c1 -W1 "$DST_HOST" >/dev/null 2>&1; then
    log "Jetson($DST_HOST) 무응답 — 종료"
    exit 1
fi

# ---------- (선택) 시간 동기화 : RTC 없는 파이 보정 ----------
JETSON_TIME=$(ssh -o ConnectTimeout=5 -o BatchMode=yes \
    "$DST_USER@$DST_HOST" 'date -u +%Y-%m-%dT%H:%M:%S' 2>/dev/null)
if [ -n "${JETSON_TIME:-}" ]; then
    sudo date -u -s "$JETSON_TIME" >/dev/null 2>&1 && log "시간 동기화: $JETSON_TIME UTC"
fi

# ---------- Jetson 여유 공간 확인 ----------
FREE_MB=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$DST_USER@$DST_HOST" \
    "df -Pm \$(eval echo $DST_DIR) 2>/dev/null | awk 'NR==2{print \$4}'")
if [ -n "${FREE_MB:-}" ] && [ "$FREE_MB" -lt "$MIN_FREE_MB" ]; then
    log "Jetson 여유 공간 부족(${FREE_MB}MB < ${MIN_FREE_MB}MB) — 중단"
    exit 1
fi

# ---------- 완료 마커가 있는 세션만 전송 ----------
shopt -s nullglob
SESSIONS=("$SRC_DIR"/session_*/)
if [ ${#SESSIONS[@]} -eq 0 ]; then
    log "전송할 세션 없음"
    exit 0
fi

for S in "${SESSIONS[@]}"; do
    NAME=$(basename "$S")

    if [ ! -f "$S/$MARKER" ]; then
        log "SKIP $NAME — 마커($MARKER) 없음(녹화 중이거나 비정상 종료)"
        continue
    fi

    log "전송 시작: $NAME"
    TRY=0
    until rsync -a --partial --append-verify --timeout=20 \
            "${S%/}" "$DST_USER@$DST_HOST:$DST_DIR/" >> "$LOG" 2>&1; do
        TRY=$((TRY+1))
        if [ "$TRY" -ge "$MAX_RETRY" ]; then
            log "FAIL $NAME — ${MAX_RETRY}회 재시도 초과, 다음 도킹 때 이어받기"
            continue 2
        fi
        log "링크 끊김($NAME) — ${RETRY_WAIT}s 후 재시도 ($TRY/$MAX_RETRY)"
        sleep "$RETRY_WAIT"
        # 링크 자체가 죽었으면 복귀 대기
        until ping -c1 -W1 "$DST_HOST" >/dev/null 2>&1; do sleep 5; done
    done
    log "전송 완료: $NAME"

    # ---------- 전송 완료 마커 생성 (Jetson 파이프라인 트리거) ----------
    # rsync 성공 뒤에만 실행되므로 이 시점엔 모든 파일이 도착해 있다.
    # PROCESSED가 이미 있으면 만들지 않는다 — 파이가 세션을 아직 지우지
    # 않은 채 재도킹하면 rsync는 "변경 없음"으로 통과해 이 지점에 다시
    # 오는데, 그때 마커를 또 만들면 Jetson이 같은 세션을 재처리한다.
    # 마커 생성이 실패해도 세션 전송 자체는 성공이므로 계속 진행한다.
    # 다음 도킹 때 rsync가 즉시 통과하고 이 지점에서 다시 시도된다.
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "$DST_USER@$DST_HOST" \
        "test -f $DST_DIR/$NAME/PROCESSED || touch $DST_DIR/$NAME/$DONE_MARKER" \
        2>>"$LOG"; then
        log "완료 마커 확인/생성: $NAME"
    else
        log "완료 마커 생성 실패($NAME) — 다음 도킹 때 재시도"
    fi

    # ---------- 검증 후 삭제 (옵션) ----------
    if [ "$DELETE_AFTER_VERIFY" = "1" ]; then
        DIFF=$(rsync -rc --dry-run --out-format='%n' "${S%/}" \
               "$DST_USER@$DST_HOST:$DST_DIR/" 2>>"$LOG" | grep -v '/$' | head -1)
        if [ -z "$DIFF" ]; then
            rm -rf "$S"
            log "검증 통과 → 파이 쪽 삭제: $NAME"
        else
            log "검증 불일치($NAME) — 삭제 보류"
        fi
    fi
done

log "===== 전송 세션 종료 ====="
