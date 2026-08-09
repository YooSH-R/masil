"""
dock_monitor.py (v2) — 도킹 상태 감시 모듈 (walkcamd 통합용)

v1의 한계와 v2의 원리:
  파이 제로는 배터리가 5V 레일을 항상 유지하므로 데이터 포트의
  VBUS가 절대 떨어지지 않는다. dwc2는 VBUS 소실로만 '분리'를
  확실히 감지할 수 있어, 포고핀을 떼도 UDC 상태가 "configured"에
  머문다 (붙임은 호스트의 버스 리셋 덕에 즉시 감지됨 — 비대칭).

  따라서 v2는 신호를 이원화한다:
    - 미도킹 판정(빠른 부정): UDC state != "configured" → 즉시 미도킹
    - 도킹 판정(능동 확인):  UDC configured  AND  Jetson ping 응답
  분리 시 Jetson 쪽 링크는 확실히 죽으므로 ping이 곧 멈춘다.
  이것이 배터리-VBUS 구조에서 유일하게 신뢰 가능한 분리 신호다.

히스테리시스:
    - UNDOCK: undock_confirm_s 초 연속 실패여야 확정 (포고핀 순단 방어)
    - DOCK:   dock_confirm_s   초 연속 성공이어야 확정

이벤트 버스 통합:
    monitor = DockMonitor(on_dock=..., on_undock=...)
    monitor.start()
  콜백은 모니터 스레드에서 호출된다. walkcamd에서는 콜백 안에서
  이벤트 버스에 publish만 하고 무거운 일은 하지 않는 것을 권장.

단독 테스트:
    python3 dock_monitor.py        # 상태 변화를 stdout에 출력
"""

from __future__ import annotations

import glob
import subprocess
import threading
import time
from dataclasses import dataclass
from typing import Callable, Optional


@dataclass(frozen=True)
class DockConfig:
    poll_interval_s: float = 1.0     # 폴링 주기
    undock_confirm_s: float = 4.0    # 분리 확정에 필요한 연속 실패 시간
    dock_confirm_s: float = 3.0      # 도킹 확정에 필요한 연속 성공 시간
    ping_host: str = "192.168.7.1"   # Jetson (USB 링크 전용 주소)
    ping_iface: str = "usb0"         # 반드시 USB 링크로만 확인
    ping_timeout_s: int = 1


class DockMonitor(threading.Thread):
    """UDC + ping 하이브리드 도킹 감시. 상태 확정 시 콜백 1회 호출."""

    DOCKED = "DOCKED"
    UNDOCKED = "UNDOCKED"

    def __init__(
        self,
        on_dock: Optional[Callable[[], None]] = None,
        on_undock: Optional[Callable[[], None]] = None,
        config: DockConfig = DockConfig(),
    ) -> None:
        super().__init__(name="dock-monitor", daemon=True)
        self._on_dock = on_dock
        self._on_undock = on_undock
        self._cfg = config
        self._stop_evt = threading.Event()

        self._udc_state_path = self._find_udc_state_path()
        self._confirmed: Optional[str] = None      # 확정 상태
        self._candidate: Optional[str] = None      # 확정 대기 중인 상태
        self._candidate_since: float = 0.0

    # ---------- 공개 API ----------

    @property
    def state(self) -> Optional[str]:
        """현재 확정 상태 (초기 확정 전에는 None)."""
        return self._confirmed

    def request_stop(self) -> None:
        self._stop_evt.set()

    # ---------- 내부 ----------

    @staticmethod
    def _find_udc_state_path() -> str:
        paths = glob.glob("/sys/class/udc/*/state")
        if not paths:
            raise RuntimeError(
                "UDC를 찾을 수 없음 — dwc2 오버레이(dr_mode=peripheral)가 "
                "적용된 파이에서 실행해야 합니다."
            )
        return paths[0]

    def _udc_configured(self) -> bool:
        try:
            with open(self._udc_state_path) as f:
                return f.read().strip() == "configured"
        except OSError:
            return False

    def _jetson_alive(self) -> bool:
        return subprocess.run(
            [
                "ping", "-c", "1",
                "-W", str(self._cfg.ping_timeout_s),
                "-I", self._cfg.ping_iface,
                self._cfg.ping_host,
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode == 0

    def _read_raw_state(self) -> str:
        # 빠른 부정: 열거조차 안 돼 있으면 ping 없이 즉시 미도킹
        if not self._udc_configured():
            return self.UNDOCKED
        # 능동 확인: VBUS 고정 구조에서 유일한 신뢰 가능한 분리 신호
        return self.DOCKED if self._jetson_alive() else self.UNDOCKED

    def _confirm_window(self, state: str) -> float:
        return (
            self._cfg.dock_confirm_s
            if state == self.DOCKED
            else self._cfg.undock_confirm_s
        )

    def run(self) -> None:
        while not self._stop_evt.is_set():
            raw = self._read_raw_state()
            now = time.monotonic()

            if raw == self._confirmed:
                # 확정 상태 유지 — 후보 리셋 (순단이 확정을 흔들지 못하게)
                self._candidate = None
            else:
                if raw != self._candidate:
                    self._candidate = raw
                    self._candidate_since = now
                elif now - self._candidate_since >= self._confirm_window(raw):
                    self._confirmed = raw
                    self._candidate = None
                    cb = self._on_dock if raw == self.DOCKED else self._on_undock
                    if cb:
                        try:
                            cb()
                        except Exception:
                            # 콜백 예외로 감시가 죽지 않게
                            pass

            self._stop_evt.wait(self._cfg.poll_interval_s)


# ---------- 단독 실행: 감지 동작 육안 테스트 ----------

if __name__ == "__main__":
    def _stamp() -> str:
        return time.strftime("%H:%M:%S")

    mon = DockMonitor(
        on_dock=lambda: print(f"[{_stamp()}] >>> DOCKED  (녹화 종료 트리거)"),
        on_undock=lambda: print(f"[{_stamp()}] >>> UNDOCKED (녹화 시작 트리거)"),
    )
    print(f"UDC: {mon._udc_state_path}")
    print("포고핀을 붙였다 떼며 확정 이벤트를 확인하세요. Ctrl+C로 종료.")
    mon.start()
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        mon.request_stop()
