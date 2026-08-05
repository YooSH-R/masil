import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../domain/entities/walk.dart';
import '../../viewmodels/walk_view_model.dart';
import '../../widgets/walk_route_map.dart';

/// 산책 중 화면. 카카오맵 위에 지나온 경로를 굵은 선으로 그린다.
///
/// 좌표는 **휴대폰 자체 GPS** 에서 온다([DeviceGpsWalkRouteSource]). 그래서
/// 거리·평균 페이스·발자국이 사용자가 실제로 걸은 값이다.
///
/// 이 화면은 [WalkViewModel.routePoints] 만 본다. 값을 채우는 주체는
/// [WalkRouteSource] 구현체이므로, 나중에 마실이 기기의 GPS 푸시로 바꿔도
/// 이 화면은 손대지 않는다.
class WalkInProgressScreen extends StatefulWidget {
  const WalkInProgressScreen({super.key});

  @override
  State<WalkInProgressScreen> createState() => _WalkInProgressScreenState();
}

class _WalkInProgressScreenState extends State<WalkInProgressScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 화면에 들어오면 경로 수신을 시작한다. 소스가 주입되지 않았으면
    // (= 백엔드 미연동) 아무 일도 일어나지 않고 지도만 뜬다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final walkVm = context.read<WalkViewModel>();
      walkVm.startRouteTracking();
      // 서버의 산책 상태(startedAt·durationSeconds·distanceMeters)를 주기적으로
      // 받아온다. 이 값이 있으면 화면은 로컬 계산값 대신 서버 값을 쓴다.
      // 서버에 산책 세션이 없으면 내부에서 알아서 아무것도 하지 않는다.
      walkVm.startWatchingWalk();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 좌표 전송은 30초 배치라서, 그 30초가 차기 전에 앱이 내려가면 모아둔 좌표가
  /// 그대로 남는다. 안드로이드는 백그라운드로 가면 배터리 최적화(Doze)가 Timer
  /// 를 늦추거나 멈추므로, 화면이 내려가는 순간 한 번 밀어 넣는다.
  ///
  /// 실패해도 버퍼에 남아 돌아왔을 때 다시 올라간다.
  ///
  /// 참고: 백그라운드에서도 계속 좌표를 "수집" 하려면 Foreground Service 가
  /// 필요하다. 지금은 마실이 기기가 좌표를 보내주고 앱은 전송만 맡으므로
  /// 여기까지로 충분하다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      context.read<WalkViewModel>().flushLocations();
    }
  }

  @override
  Widget build(BuildContext context) {
    final walkVm = context.watch<WalkViewModel>();
    final points = walkVm.routePoints;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(walkVm),
            _buildStatsCard(walkVm),
            Expanded(
                child: _buildMapCard(
                    points,
                    // 위치가 막힌 이유가 있으면 그걸, 없으면 좌표가 걸러지는
                    // 이유(진단)를 보여준다. 둘 다 없으면 기본 안내가 나온다.
                    walkVm.routeUnavailableMessage ?? walkVm.gpsDiagnostic)),
            _buildControls(walkVm),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(WalkViewModel walkVm) {
    final isReceiving = walkVm.hasRoute;
    final blocked = walkVm.routeUnavailableMessage != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('산책 중이에요',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5D4037))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: blocked
                  ? const Color(0xFFFFEBEE)
                  : isReceiving
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(
                  blocked ? Icons.location_off : Icons.circle,
                  color: blocked
                      ? const Color(0xFFD32F2F)
                      : isReceiving
                          ? Colors.green
                          : Colors.grey,
                  size: blocked ? 12 : 8,
                ),
                const SizedBox(width: 6),
                Text(
                  blocked
                      ? '위치 꺼짐'
                      : isReceiving
                          ? 'GPS 기록 중'
                          : 'GPS 찾는 중',
                  style: TextStyle(
                      color: blocked
                          ? const Color(0xFFD32F2F)
                          : isReceiving
                              ? Colors.green
                              : Colors.grey,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard(WalkViewModel walkVm) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 20,
              offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        children: [
          const Text('경과 시간',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            _formatDuration(walkVm.elapsed),
            style: const TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5D4037),
                letterSpacing: 2),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStat(_formatDistance(walkVm.distanceMeters), 'km', '거리'),
              _buildStat(
                  _formatPace(walkVm.distanceMeters, walkVm.elapsed), '', '평균 페이스'),
              _buildStat('${walkVm.routePoints.length}', '개', '발자국'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMapCard(
      List<WalkLocationPoint> points, String? unavailableMessage) {
    // 주의: 이 컨테이너에 clipBehavior/borderRadius 를 걸지 않는다.
    // KakaoMap 은 WebView(안드로이드 플랫폼 뷰)라서 클리핑을 걸면 렌더링이
    // 비어버린다(지도가 안 보이고 배경색만 나옴).
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(color: Color(0xFFE8F6F3)),
      child: Stack(
        children: [
          Positioned.fill(child: _buildMap(points)),
          if (points.isEmpty)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: _RouteHintBadge(unavailableMessage: unavailableMessage),
            ),
        ],
      ),
    );
  }

  Widget _buildMap(List<WalkLocationPoint> points) {
    // 지도·경로선은 경로 상세 화면과 공용 위젯을 쓴다.
    return WalkRouteMap(points: points, followLast: true);
  }

  Widget _buildControls(WalkViewModel walkVm) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 60,
              child: ElevatedButton(
                onPressed: () => context.push('/walk/disconnected'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF5D4037),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  elevation: 0,
                ),
                child: const Text('일시정지',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SizedBox(
              height: 60,
              child: ElevatedButton(
                onPressed: () async {
                  // 남은 좌표를 다 올린 뒤 서버에 종료를 알린다.
                  // 서버는 이 시점부터 감성 사진·일지를 만든다.
                  await walkVm.endWalk();
                  if (!mounted) return;
                  context.push('/walk/summary');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD32F2F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  elevation: 0,
                ),
                child: const Text('산책 종료',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String value, String unit, String label) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5D4037))),
            const SizedBox(width: 2),
            Text(unit,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  /// 00:24:18
  static String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  static String _formatDistance(int meters) =>
      (meters / 1000).toStringAsFixed(2);

  /// 1km 당 분'초". 아직 움직이지 않았으면 --'--".
  static String _formatPace(int meters, Duration elapsed) {
    if (meters < 10 || elapsed.inSeconds == 0) return '--\'--"';
    final secondsPerKm = elapsed.inSeconds / (meters / 1000);
    final m = secondsPerKm ~/ 60;
    final s = (secondsPerKm % 60).round();
    return '$m\'${s.toString().padLeft(2, '0')}"';
  }
}

/// 아직 좌표가 없을 때 지도 위에 띄우는 안내.
///
/// 위치가 막힌 경우([unavailableMessage])와 그냥 아직 안 잡힌 경우를 구분한다.
/// 권한이 거부됐는데 "곧 그려져요"라고만 하면 사용자는 계속 기다리게 된다.
class _RouteHintBadge extends StatelessWidget {
  const _RouteHintBadge({this.unavailableMessage});

  final String? unavailableMessage;

  @override
  Widget build(BuildContext context) {
    final blocked = unavailableMessage != null;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(blocked ? Icons.location_off : Icons.my_location,
                color: blocked
                    ? const Color(0xFFD32F2F)
                    : const Color(0xFFC67C4E),
                size: 16),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                unavailableMessage ?? 'GPS 신호를 찾고 있어요. 걷기 시작하면 경로가 그려져요',
                style: TextStyle(
                    color: blocked
                        ? const Color(0xFFD32F2F)
                        : const Color(0xFF5D4037),
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

