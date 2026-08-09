import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mysil_project_new/core/services/gps/gps_track_config.dart';
import 'package:mysil_project_new/core/services/gps/walk_track_processor.dart';
import 'package:mysil_project_new/core/utils/geo.dart';
import 'package:mysil_project_new/domain/entities/walk.dart';

/// 테스트는 미터 단위로 생각하고 쓰는 게 읽기 쉽다. 원점 기준 (동쪽 dx, 북쪽 dy)
/// 오프셋을 위경도로 바꿔 주는 도우미.
const double _originLat = 37.5;
const double _originLng = 127.0;
const double _metersPerLatDegree = 111320;
final double _metersPerLngDegree =
    _metersPerLatDegree * math.cos(_originLat * math.pi / 180);
final DateTime _t0 = DateTime.utc(2026, 1, 1, 9);

int _seq = 0;

WalkLocationPoint gps(
  double dx,
  double dy, {
  required double atSeconds,
  double? accuracy = 8,
}) {
  _seq += 1;
  return WalkLocationPoint(
    latitude: _originLat + dy / _metersPerLatDegree,
    longitude: _originLng + dx / _metersPerLngDegree,
    accuracy: accuracy,
    sequence: _seq,
    recordedAt: _t0.add(Duration(milliseconds: (atSeconds * 1000).round())),
  );
}

/// 확정점이 (dx, dy) 근처에 하나라도 있는지.
bool hasAnchorNear(
  List<WalkLocationPoint> anchors,
  double dx,
  double dy, {
  double within = 3,
}) {
  return anchors.any((a) =>
      Geo.distanceMeters(
        lat1: a.latitude,
        lng1: a.longitude,
        lat2: _originLat + dy / _metersPerLatDegree,
        lng2: _originLng + dx / _metersPerLngDegree,
      ) <=
      within);
}

void main() {
  setUp(() => _seq = 0);

  group('이상치 제거', () {
    test('정확도 35m 를 넘으면 버리고 현재 위치도 갱신하지 않는다', () {
      final p = WalkTrackProcessor();
      p.add(gps(0, 0, atSeconds: 0));
      final before = p.livePosition;

      final update = p.add(gps(5, 0, atSeconds: 1, accuracy: 40));

      expect(update.isRejected, isTrue);
      expect(update.rejectReason, contains('정확도'));
      expect(p.livePosition, same(before));
    });

    test('정확도 20~35m 는 화면에는 쓰되 그것만으로 경로를 확정하지 않는다', () {
      final p = WalkTrackProcessor();
      p.add(gps(0, 0, atSeconds: 0));
      final anchorsBefore = p.anchors.length;

      // 후보 전용 좌표를 코너 모양으로 넣어도 확정되지 않아야 한다.
      final update = p.add(gps(0, 10, atSeconds: 1, accuracy: 30));
      p.add(gps(10, 10, atSeconds: 2, accuracy: 30));

      expect(update.isRejected, isFalse, reason: '화면 위치는 갱신된다');
      expect(update.livePosition, isNotNull);
      expect(p.anchors.length, anchorsBefore);
    });

    test('걸을 수 없는 속도로 들어온 좌표는 버린다', () {
      final p = WalkTrackProcessor();
      p.add(gps(0, 0, atSeconds: 0));

      // 1초에 50m = 50m/s
      final update = p.add(gps(50, 0, atSeconds: 1));

      expect(update.isRejected, isTrue);
      expect(update.rejectReason, contains('m/s'));
    });

    test('시각이 같거나 거꾸로 와도 위치가 멀쩡하면 버리지 않는다', () {
      final p = WalkTrackProcessor();
      p.add(gps(0, 0, atSeconds: 5));

      final same = p.add(gps(2, 0, atSeconds: 5));
      final reversed = p.add(gps(4, 0, atSeconds: 3));

      expect(same.isRejected, isFalse);
      expect(reversed.isRejected, isFalse);
    });

    test('시각을 믿을 수 없는데 거리까지 멀면 버린다', () {
      final p = WalkTrackProcessor();
      p.add(gps(0, 0, atSeconds: 5));

      final update = p.add(gps(500, 0, atSeconds: 5));

      expect(update.isRejected, isTrue);
      expect(update.rejectReason, contains('순간이동'));
    });
  });

  group('경로점 확정', () {
    test('제자리에서 GPS 가 2~5m 흔들려도 경로점이 쌓이지 않는다', () {
      final p = WalkTrackProcessor();
      final wobble = [
        [0.0, 0.0], [2.0, 1.0], [-1.0, 2.0], [1.0, -2.0], [-2.0, -1.0],
        [2.0, 2.0], [-2.0, 1.0], [1.0, 1.0], [-1.0, -1.0], [0.0, 2.0],
      ];
      for (var i = 0; i < wobble.length; i++) {
        p.add(gps(wobble[i][0], wobble[i][1], atSeconds: i.toDouble()));
      }

      // 출발점 1개 + 흔들림으로 인한 약간의 점. 10개가 다 남으면 실패다.
      expect(p.anchors.length, lessThanOrEqualTo(3));
    });

    test('한 좌표만 크게 튀었다가 돌아오면 경로에 남지 않는다', () {
      final p = WalkTrackProcessor();
      // 2초 간격이라 속도 필터(10m/s)에 걸리지 않는 크기로 튄다.
      p.add(gps(0, 0, atSeconds: 0));
      p.add(gps(0, 2, atSeconds: 2));
      p.add(gps(18, 4, atSeconds: 4)); // 튐
      p.add(gps(0, 6, atSeconds: 6)); // 복귀
      p.add(gps(0, 8, atSeconds: 8));
      p.finish();

      // 튄 좌표(동쪽 18m) 근처에는 확정점이 없어야 한다.
      expect(hasAnchorNear(p.anchors, 18, 4, within: 8), isFalse);
      // 정상 경로는 살아 있어야 한다.
      expect(p.anchors.length, greaterThanOrEqualTo(2));
    });

    test('직선 보행은 원본보다 점이 줄어든다', () {
      final p = WalkTrackProcessor();
      const samples = 40; // 1초마다 1.4m = 약 55m
      for (var i = 0; i < samples; i++) {
        p.add(gps(0, i * 1.4, atSeconds: i.toDouble()));
      }
      p.finish();

      expect(p.anchors.length, lessThan(samples),
          reason: '중간점이 솎여야 한다');
      expect(p.anchors.length, greaterThan(2),
          reason: '시작·끝 두 개로 줄어들면 안 된다');
    });

    test('90도 방향 전환점은 보존된다', () {
      final p = WalkTrackProcessor();
      var t = 0.0;
      // 북쪽으로 30m
      for (var i = 0; i <= 21; i++) {
        p.add(gps(0, i * 1.4, atSeconds: t));
        t += 1;
      }
      // 동쪽으로 30m (코너는 (0, 29.4))
      for (var i = 1; i <= 21; i++) {
        p.add(gps(i * 1.4, 29.4, atSeconds: t));
        t += 1;
      }
      p.finish();

      // EMA 가 코너를 조금 둥글게 깎으므로 여유를 둔다.
      expect(hasAnchorNear(p.anchors, 0, 29.4, within: 6), isTrue,
          reason: '코너 근처에 확정점이 있어야 한다');
    });

    test('곡선 경로는 형태가 유지된다', () {
      final p = WalkTrackProcessor();
      const radius = 20.0;
      var t = 0.0;
      // 4분원을 따라 걷는다.
      for (var deg = 0; deg <= 90; deg += 4) {
        final rad = deg * math.pi / 180;
        p.add(gps(radius * math.sin(rad), radius * (1 - math.cos(rad)),
            atSeconds: t));
        t += 1;
      }
      p.finish();

      // 직선이 아니므로 중간점이 여러 개 남아야 곡선으로 보인다.
      expect(p.anchors.length, greaterThan(4));
    });

    test('아주 천천히 걸어도 경로가 멈추지 않는다', () {
      final p = WalkTrackProcessor();
      // 0.4m/s — 1초에 0.4m 씩만 움직인다.
      for (var i = 0; i <= 40; i++) {
        p.add(gps(0, i * 0.4, atSeconds: i.toDouble()));
      }
      p.finish();

      expect(p.anchors.length, greaterThan(2),
          reason: '느린 보행에서도 강제 확정으로 점이 쌓여야 한다');
    });

    test('종료 시 남은 후보점을 확정한다', () {
      final p = WalkTrackProcessor();
      p.add(gps(0, 0, atSeconds: 0));
      p.add(gps(0, 1.0, atSeconds: 1));

      final beforeFinish = p.anchors.length;
      final flushed = p.finish();

      expect(flushed, isNotEmpty, reason: '마지막 구간이 잘리면 안 된다');
      expect(p.anchors.length, beforeFinish + flushed.length);
    });
  });

  group('화면용과 저장용 분리', () {
    test('걸러지지 않은 좌표마다 현재 위치는 갱신된다', () {
      final p = WalkTrackProcessor();
      p.add(gps(0, 0, atSeconds: 0));

      final positions = <WalkLocationPoint>[];
      for (var i = 1; i <= 5; i++) {
        final update = p.add(gps(0, i * 1.0, atSeconds: i.toDouble()));
        expect(update.livePosition, isNotNull);
        positions.add(update.livePosition!);
      }

      // 확정점은 몇 개 안 되지만 현재 위치는 매번 움직인다.
      expect(positions.length, 5);
      expect(p.anchors.length, lessThan(5));
      expect(positions.first.latitude, isNot(positions.last.latitude));
    });

    test('EMA 는 튄 폭을 줄이지만 방향은 따라간다', () {
      final p = WalkTrackProcessor(
        config: const GpsTrackConfig(emaAlpha: 0.3),
      );
      p.add(gps(0, 0, atSeconds: 0));
      final update = p.add(gps(0, 10, atSeconds: 2));

      final moved = Geo.distanceMeters(
        lat1: _originLat,
        lng1: _originLng,
        lat2: update.livePosition!.latitude,
        lng2: update.livePosition!.longitude,
      );
      // alpha 0.3 이면 10m 중 약 3m 만 따라간다.
      expect(moved, greaterThan(1));
      expect(moved, lessThan(6));
    });

    test('sequence 는 원본 값을 그대로 유지한다', () {
      final p = WalkTrackProcessor();
      final first = gps(0, 0, atSeconds: 0);
      final update = p.add(first);

      expect(update.livePosition!.sequence, first.sequence);
      expect(update.committedAnchors.single.sequence, first.sequence);
    });
  });
}
