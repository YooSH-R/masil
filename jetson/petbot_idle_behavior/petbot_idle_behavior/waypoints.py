"""
Idle 배회(-208)용 순찰 웨이포인트.

TODO: SLAM 지도가 생기면 실제 지도 위의 안전한 좌표들로 교체할 것.
지금은 map==odom==base_link를 identity static TF로 묶어 테스트하는 환경
(start_idle_wander.sh 참고) 기준으로, 로봇 주변 1~1.5m 반경의 안전한
임의 좌표 4개를 하드코딩해 둔다.

frame_id는 idle_wander.py에서 'map'으로 고정해서 move_to()에 넘긴다.
"""

PATROL_WAYPOINTS = [
    (1.0, 0.5),
    (-1.0, 1.0),
    (1.5, -1.0),
    (-1.5, -0.5),
]
