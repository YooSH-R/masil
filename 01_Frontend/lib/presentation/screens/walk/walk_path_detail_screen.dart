import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/services/sample_walk_diaries.dart';
import '../../../domain/entities/walk.dart';
import '../../../domain/entities/walk_photo.dart';
import '../../viewmodels/walk_diary_view_model.dart';
import '../../viewmodels/walk_view_model.dart';
import '../../widgets/walk_photo_image.dart';
import '../../widgets/walk_route_map.dart';

/// 지난 산책의 경로 상세. GET /walks/{walkId}/summary 의 route 를
/// 카카오맵 위에 굵은 선으로 그린다.
class WalkPathDetailScreen extends StatefulWidget {
  const WalkPathDetailScreen({super.key, this.walkId});

  /// 볼 산책의 id. null 이면 진행/최근 산책을 보여준다.
  final int? walkId;

  @override
  State<WalkPathDetailScreen> createState() => _WalkPathDetailScreenState();
}

class _WalkPathDetailScreenState extends State<WalkPathDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final walkVm = context.read<WalkViewModel>();
      final id = widget.walkId ?? walkVm.currentWalk?.walkId;
      if (id == null) return;

      walkVm.loadSummary(id);
      // 감성 사진은 산책일지 상세에 들어 있다. 7월 예시 기록은 서버에 없어서
      // 조회하면 401 만 나므로 건너뛴다(아래에서 asset 그림을 쓴다).
      if (!SampleWalkDiaries.isSampleId(id)) {
        context.read<WalkDiaryViewModel>().loadDetail(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final walkVm = context.watch<WalkViewModel>();

    // 어떤 산책을 보고 있는지. extra 로 안 넘어오면 진행/최근 산책.
    final shownWalkId = widget.walkId ?? walkVm.currentWalk?.walkId;

    // **이 산책의 요약일 때만 쓴다.** 뷰모델은 산책 하나 분량의 요약만 들고
    // 있어서, 조회가 끝나기 전이나 실패했을 때는 앞서 본 산책의 값이 남아
    // 있다. 그걸 그대로 그리면 엉뚱한 지도가 뜬다.
    final loaded = walkVm.summary;
    final summary =
        (loaded != null && loaded.walkId == shownWalkId) ? loaded : null;

    // 메모리에 남은 좌표([WalkViewModel.routePoints])는 **지금 보고 있는 산책의
    // 것일 때만** 폴백으로 쓴다.
    //
    // 그 좌표는 산책이 끝나도 다음 산책이 시작될 때까지 남는다. 신원을 안 따지고
    // 쓰면, 방금 걷고 나서 지난 일지를 열었을 때 조회가 끝나기 전까지 방금 걸은
    // 경로가 그려지고, 조회가 실패하면 그대로 굳는다.
    final isCurrentWalk =
        shownWalkId != null && shownWalkId == walkVm.currentWalk?.walkId;
    final fallbackRoute = isCurrentWalk
        ? walkVm.routePoints
        : const <WalkLocationPoint>[];

    // 저장된 경로가 있으면 그걸 쓰고, 없으면(방금 끝낸 산책 등) 메모리의 좌표를 쓴다.
    final route =
        (summary?.route.isNotEmpty ?? false) ? summary!.route : fallbackRoute;

    // 거리·시간도 같은 기준이다. 지난 산책 화면에 진행 중인 산책의 값이 뜨면
    // 경로만 맞추고 숫자가 어긋나는 더 헷갈리는 상태가 된다. 조회가 끝나기
    // 전에는 0 으로 두고, 값이 오면 그때 채워진다.
    final distanceMeters =
        summary?.distanceMeters ?? (isCurrentWalk ? walkVm.distanceMeters : 0);
    final durationSeconds = summary?.durationSeconds ??
        (isCurrentWalk ? walkVm.elapsed.inSeconds : 0);
    final sampleImage = shownWalkId == null
        ? null
        : SampleWalkDiaries.imageAssetOf(shownWalkId);

    // 서버가 만들어 준 감성 사진. 일지 상세가 **이 산책의 것일 때만** 쓴다.
    // (다른 산책을 보다가 넘어온 경우 남아 있는 상세를 잘못 그리지 않게)
    final detail = context.watch<WalkDiaryViewModel>().detail;
    final photos = (detail != null && detail.walkId == shownWalkId)
        ? detail.photos
        : const <WalkPhoto>[];

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Color(0xFF5D4037)),
          onPressed: () => context.pop(),
        ),
        title: const Text('산책 경로 상세', style: TextStyle(color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
        child: Column(
          children: [
            // Map Area
            // 주의: borderRadius/clipBehavior 로 감싸지 않는다. 내부가 WebView
            // (플랫폼 뷰)라서 클리핑하면 지도가 렌더링되지 않는다.
            Container(
              height: 350,
              width: double.infinity,
              color: const Color(0xFFE8F6F3),
              child: Stack(
                children: [
                  // 경로 전체가 보이도록 줌을 맞추고, 출발·도착에 마커를 찍는다.
                  Positioned.fill(
                    child: WalkRouteMap(
                      points: route,
                      fitWholeRoute: true,
                    ),
                  ),
                  if (route.isEmpty)
                    const Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: _NoRouteBadge(),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Stats Row
            _buildWhiteCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMiniStat(
                      '${(distanceMeters / 1000).toStringAsFixed(2)} km', '산책 거리'),
                  Container(width: 1, height: 30, color: Colors.grey.shade100),
                  _buildMiniStat('${durationSeconds ~/ 60} 분', '산책 시간'),
                  Container(width: 1, height: 30, color: Colors.grey.shade100),
                  _buildMiniStat(_paceLabel(distanceMeters, durationSeconds),
                      '평균 페이스'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Badges
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFFE8F6F3).withValues(alpha: 0.6), borderRadius: BorderRadius.circular(15)),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.circle, color: Colors.green, size: 8),
                  SizedBox(width: 8),
                  Text('위치 권한 허용됨 · GPS 정확도 높음 · 카카오맵 연동', style: TextStyle(color: Color(0xFF16A085), fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Info Note
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
              child: const Row(
                children: [
                  Icon(Icons.location_on, color: Colors.redAccent, size: 18),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '경로가 안 보이나요? 실내 산책이거나 GPS가 약했을 수 있어요. 그래도 기록엔 저장돼요.',
                      style: TextStyle(color: Color(0xFF8D6E63), fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 40),
            
            // AI Action Section
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('이 산책의 감성 사진', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                photos.isEmpty
                    ? '산책이 끝나면 마실이가 찍은 장면으로 사진을 만들어요'
                    : '마실이가 ${photos.length}장을 만들어 뒀어요. 골라서 저장해 보세요',
                style: const TextStyle(color: Color(0xFF8D6E63)),
              ),
            ),
            const SizedBox(height: 20),

            // 감성 사진 카드
            _buildWhiteCard(
              child: Column(
                children: [
                  _buildPhotoStrip(photos, sampleImage),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      // 어떤 산책의 사진인지 함께 넘긴다. 안 넘기면 고르기 화면이
                      // 엉뚱한(또는 비어 있는) 일지를 보게 된다.
                      onPressed: () =>
                          context.push('/walk/ai-photo', extra: shownWalkId),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC67C4E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.auto_awesome, size: 20),
                          SizedBox(width: 12),
                          Text('AI 감성 사진 만들기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  /// 감성 사진 미리보기.
  ///
  /// 서버 사진이 여러 장 오므로 옆으로 넘겨 보는 줄로 그린다. 몇 장이 오든
  /// 늘어나고, 한 장만 와도 어색하지 않다.
  ///
  /// 7월 예시 기록([sampleImage])은 서버에 없어서 asset 그림 한 장을 쓴다.
  /// 둘 다 없으면 빈 자리 안내를 보여준다.
  Widget _buildPhotoStrip(List<WalkPhoto> photos, String? sampleImage) {
    const height = 180.0;

    if (photos.isEmpty) {
      return Container(
        height: height,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: _photoBoxDecoration,
        child: sampleImage == null
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_awesome, size: 36, color: Color(0xFFD7CCC8)),
                    SizedBox(height: 10),
                    Text('아직 사진이 없어요',
                        style: TextStyle(
                            fontSize: 13, color: Color(0xFF8D6E63))),
                  ],
                ),
              )
            : Image.asset(
                sampleImage,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined,
                        size: 40, color: Color(0xFFD7CCC8))),
              ),
      );
    }

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final photo = photos[index];
          return GestureDetector(
            // 사진을 눌러도 고르기 화면으로 간다. 거기서 저장할 수 있다.
            onTap: () => context.push('/walk/ai-photo', extra: photo.walkId),
            child: Container(
              width: 150,
              clipBehavior: Clip.antiAlias,
              decoration: _photoBoxDecoration,
              child: WalkPhotoImage(photo: photo),
            ),
          );
        },
      ),
    );
  }

  static final BoxDecoration _photoBoxDecoration = BoxDecoration(
    color: const Color(0xFFFDF7F0),
    borderRadius: BorderRadius.circular(15),
    border: Border.all(color: const Color(0xFFF0E0D0)),
  );

  /// 1km 당 분'초". 거리·시간이 없으면 --'--".
  static String _paceLabel(int meters, int seconds) {
    if (meters < 10 || seconds == 0) return '--\'--"';
    final secondsPerKm = seconds / (meters / 1000);
    final m = secondsPerKm ~/ 60;
    final s = (secondsPerKm % 60).round();
    return '$m\'${s.toString().padLeft(2, '0')}"';
  }

  // ignore: unused_element
  Widget _buildMarker(String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        Icon(Icons.location_on, color: color, size: 30),
      ],
    );
  }

  Widget _buildMiniStat(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF5D4037))),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  Widget _buildWhiteCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: child,
    );
  }
}

class MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.5)..strokeWidth = 1;
    for (double i = 0; i < size.width; i += 50) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 50) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }

    final pathPaint = Paint()..color = const Color(0xFFC67C4E)..strokeWidth = 5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(size.width * 0.2, size.height * 0.8)..quadraticBezierTo(size.width * 0.5, size.height * 0.4, size.width * 0.8, size.height * 0.2);
    canvas.drawPath(path, pathPaint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 저장된 경로가 없을 때 지도 위에 띄우는 안내.
class _NoRouteBadge extends StatelessWidget {
  const _NoRouteBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off_outlined, color: Color(0xFFC67C4E), size: 16),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                '저장된 경로가 없어요',
                style: TextStyle(
                    color: Color(0xFF5D4037),
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
