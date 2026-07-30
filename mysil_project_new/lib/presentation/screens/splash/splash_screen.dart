import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

/// 마실(MYSIL) 스플래시 — "공원 오후" (design option 2b)
/// 기존 splash/splash_screen.dart 를 이 파일로 교체하세요.
///
/// 필요한 것:
///  1) pubspec.yaml 에 로고 이미지 asset (아래 _kLogoAsset 경로 수정)
///  2) 헤드라인 폰트 Jua — pubspec 에 google_fonts 추가 후
///     GoogleFonts.jua() 로 바꾸거나, 폰트 파일을 직접 등록하세요.
///  3) onTap 안의 네비게이션을 기존 스플래시의 이동 로직으로 교체.

const _kLogoAsset = 'assets/images/mysil_logo.png'; // TODO: 실제 로고 경로

// 디자인 기준 캔버스 (340 x 720) — 실제 화면 크기에 비례 스케일됩니다.
const _dw = 340.0, _dh = 720.0;

// 로고 원 — 크기를 바꾸면 가로 위치는 아래에서 자동으로 다시 중앙 정렬된다.
const _kLogoCircle = 195.0; // 지름 (디자인 캔버스 기준, 이전 170)
const _kLogoCircleTop = 145.0; // 상단 여백
const _kLogoPadding = 26.0; // 원과 로고 사이 여백

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _breathe; // 로고 숨쉬기 3.6s
  late final AnimationController _paw; // 발자국 사이클 3.6s
  late final AnimationController _glow; // 태양/가로등 글로우 4.5s
  late final AnimationController _hint; // 안내문구 펄스 2.4s

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3600))
      ..repeat();
    _paw = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3600))
      ..repeat();
    _glow = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 4500))
      ..repeat();
    _hint = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat();
  }

  @override
  void dispose() {
    _breathe.dispose();
    _paw.dispose();
    _glow.dispose();
    _hint.dispose();
    super.dispose();
  }

  // 0..1 → 사인형 왕복 (ease-in-out 왕복과 동일한 느낌)
  double _pingPong(double t) =>
      (1 - (2 * t - 1).abs()); // 0→1→0 triangle; Curves로 부드럽게

  // CSS pawStep 재현: 0~10% 페이드인, 10~45% 유지, 45~55% 페이드아웃, 이후 숨김
  double _pawOpacity(double t, double delayFrac) {
    var p = (t - delayFrac) % 1.0;
    if (p < 0) p += 1.0;
    if (p < .10) return p / .10;
    if (p < .45) return 1;
    if (p < .55) return 1 - (p - .45) / .10;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 이 앱은 go_router를 쓴다. Navigator로 직접 띄우면 라우터 위치가
        // /splash 에 머물러 이후 context.go/push 가 어긋나므로 라우터로 이동한다.
        // /auto-login 에서 저장된 refreshToken으로 세션 복구를 시도하고
        // 성공하면 /home, 실패하면 /login 으로 보낸다.
        onTap: () => context.go('/auto-login'),
        child: LayoutBuilder(builder: (context, c) {
          final sx = c.maxWidth / _dw, sy = c.maxHeight / _dh;
          Widget at(double left, double top, Widget child) =>
              Positioned(left: left * sx, top: top * sy, child: child);
          Widget atB(double left, double bottom, Widget child) =>
              Positioned(left: left * sx, bottom: bottom * sy, child: child);

          return Stack(children: [
            // 하늘 그라디언트
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, .45, 1],
                    colors: [
                      Color(0xFFFFE3C2),
                      Color(0xFFFDEED6),
                      Color(0xFFF8EAD6)
                    ],
                  ),
                ),
              ),
            ),
            // 태양 글로우 (top:48 right:52, 64px)
            at(_dw - 52 - 64, 48, _Glow(anim: _glow, size: 64 * sx)),
            // 잔디 두 겹 (rounded top)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 250 * sy,
              child: _Hill(color: const Color(0xFFB3BF95), curve: 64 * sy),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 175 * sy,
              child: _Hill(color: const Color(0xFF9AAA7C), curve: 44 * sy),
            ),
            // 산책로 + 발자국
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 250 * sy,
              child: AnimatedBuilder(
                animation: _paw,
                builder: (_, __) => CustomPaint(
                  painter: _PathPainter(
                    pawOpacities: [
                      _pawOpacity(_paw.value, 0.0),
                      _pawOpacity(_paw.value, 1 / 6), // 0.6s
                      _pawOpacity(_paw.value, 2 / 6), // 1.2s
                      _pawOpacity(_paw.value, 3 / 6), // 1.8s
                    ],
                  ),
                ),
              ),
            ),
            // 가로등 (bottom:158 left:36)
            atB(36, 158 * 1.0, _LampPost(glow: _glow, sx: sx)),
            // 벤치 (bottom:120 right:36)
            Positioned(right: 36 * sx, bottom: 120 * sy, child: _Bench(sx: sx)),
            // 나무 2그루 (오른쪽)
            Positioned(
                right: 86 * sx,
                bottom: 190 * sy,
                child: _Tree(
                    canopy: 48 * sx,
                    trunkH: 22 * sy,
                    color: const Color(0xFF7A8A5E))),
            Positioned(
                right: 48 * sx,
                bottom: 200 * sy,
                child: _Tree(
                    canopy: 34 * sx,
                    trunkH: 16 * sy,
                    color: const Color(0xFF93A374))),
            // 덤불 (bottom:60 left:80)
            atB(80, 60,
                _Bush(w: 44 * sx, h: 20 * sy, color: const Color(0xFF87976B))),
            // 로고 — 숨쉬기 (top:150, 170px, scale 1→1.045)
            at(
                _dw / 2 - _kLogoCircle / 2, // 지름이 바뀌어도 가로 중앙 유지
                _kLogoCircleTop,
                AnimatedBuilder(
                  animation: _breathe,
                  builder: (_, child) {
                    final t =
                        Curves.easeInOut.transform(_pingPong(_breathe.value));
                    return Transform.scale(scale: 1 + .045 * t, child: child);
                  },
                  child: Container(
                    width: _kLogoCircle * sx,
                    height: _kLogoCircle * sx,
                    padding: EdgeInsets.all(_kLogoPadding * sx),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // 하늘·산책로와 같은 계열의 따뜻한 크림색.
                      // 가운데는 거의 흰색이라 로고가 또렷하고, 테두리로 갈수록
                      // 살짝 색이 들어가 하늘 위에서 떠 보이지 않는다.
                      gradient: const RadialGradient(
                        colors: [Color(0xFFFFFDF8), Color(0xFFFBEFDB)],
                        stops: [.55, 1],
                      ),
                      border: Border.all(
                        color: const Color(0xFFF0DDBE), // 산책로(#F3E3C6) 계열
                        width: 1.4 * sx,
                      ),
                      boxShadow: [
                        BoxShadow(
                            color:
                                const Color(0xFF8A5A44).withValues(alpha: .18),
                            blurRadius: 28,
                            offset: const Offset(0, 10)),
                      ],
                    ),
                    child: Image.asset(_kLogoAsset, fit: BoxFit.contain),
                  ),
                )),
            // 카피 (top:390)
            Positioned(
              top: 390 * sy,
              left: 0,
              right: 0,
              child: Column(children: [
                Text('반려 로봇과 함께 걷는',
                    style: TextStyle(
                        fontSize: 15 * sx, color: const Color(0xFFA5765C))),
                SizedBox(height: 10 * sy),
                // 헤드라인 폰트 Jua — google_fonts 패키지가 내려받아 적용한다.
                Text('건강한 마실',
                    style: GoogleFonts.jua(
                      fontSize: 32 * sx,
                      letterSpacing: 1,
                      color: const Color(0xFF6B4632),
                    )),
              ]),
            ),
            // 안내 문구 (bottom:28) — 펄스
            Positioned(
              bottom: 28 * sy,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _hint,
                builder: (_, __) {
                  final t = Curves.easeInOut.transform(_pingPong(_hint.value));
                  return Opacity(
                    opacity: .45 + .45 * t,
                    child: Text('탭하고 마실이 만나러 가기',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13.5 * sx,
                            color: const Color(0xFF39432A))),
                  );
                },
              ),
            ),
          ]);
        }),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.anim, required this.size});
  final Animation<double> anim;
  final double size;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: anim,
        builder: (_, __) {
          final t = Curves.easeInOut.transform(1 - (2 * anim.value - 1).abs());
          return Transform.scale(
            scale: 1 + .12 * t,
            child: Opacity(
              opacity: .55 + .35 * t,
              child: Container(
                width: size,
                height: size,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    stops: [0, .55, .72],
                    colors: [
                      Color(0xFFFFD9A0),
                      Color(0xFFFFCF8F),
                      Color(0x00FFCF8F)
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
}

class _Hill extends StatelessWidget {
  const _Hill({required this.color, required this.curve});
  final Color color;
  final double curve;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, c) => Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.vertical(
                top: Radius.elliptical(c.maxWidth, curve * 2)),
          ),
        ),
      );
}

class _Tree extends StatelessWidget {
  const _Tree(
      {required this.canopy, required this.trunkH, required this.color});
  final double canopy, trunkH;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: canopy,
        height: canopy + trunkH * .6,
        child: Stack(alignment: Alignment.bottomCenter, children: [
          Container(
              width: canopy * .14,
              height: trunkH,
              decoration: BoxDecoration(
                  color: const Color(0xFF8A5A44),
                  borderRadius: BorderRadius.circular(4))),
          Positioned(
              bottom: trunkH * .6,
              child: Container(
                  width: canopy,
                  height: canopy,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: color))),
        ]),
      );
}

class _Bush extends StatelessWidget {
  const _Bush({required this.w, required this.h, required this.color});
  final double w, h;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.vertical(top: Radius.circular(w / 2))),
      );
}

class _LampPost extends StatelessWidget {
  const _LampPost({required this.glow, required this.sx});
  final Animation<double> glow;
  final double sx;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 20 * sx,
        height: 70 * sx,
        child: Stack(alignment: Alignment.bottomCenter, children: [
          Container(
              width: 5 * sx,
              height: 52 * sx,
              decoration: BoxDecoration(
                  color: const Color(0xFF6B4632),
                  borderRadius: BorderRadius.circular(3))),
          Positioned(
            top: 0,
            child: AnimatedBuilder(
              animation: glow,
              builder: (_, __) {
                final t =
                    Curves.easeInOut.transform(1 - (2 * glow.value - 1).abs());
                return Container(
                  width: 18 * sx,
                  height: 18 * sx,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFCF8F),
                    boxShadow: [
                      BoxShadow(
                          color: const Color(0xFFFFCF8F)
                              .withValues(alpha: .3 + .3 * t),
                          blurRadius: 16,
                          spreadRadius: 6),
                    ],
                  ),
                );
              },
            ),
          ),
        ]),
      );
}

class _Bench extends StatelessWidget {
  const _Bench({required this.sx});
  final double sx;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 64 * sx,
        child: Column(children: [
          Container(
              width: 64 * sx,
              height: 9 * sx,
              decoration: BoxDecoration(
                  color: const Color(0xFF8A5A44),
                  borderRadius: BorderRadius.circular(5))),
          SizedBox(height: 4 * sx),
          Container(
              width: 64 * sx,
              height: 8 * sx,
              decoration: BoxDecoration(
                  color: const Color(0xFF9C6A50),
                  borderRadius: BorderRadius.circular(5))),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 7 * sx),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                    2,
                    (_) => Container(
                        width: 6 * sx,
                        height: 15 * sx,
                        decoration: const BoxDecoration(
                            color: Color(0xFF6B4632),
                            borderRadius: BorderRadius.vertical(
                                bottom: Radius.circular(3)))))),
          ),
        ]),
      );
}

/// 산책로(크림색 굽이길) + 발자국 4개.
/// 디자인 좌표계 340x250 기준 → size에 맞춰 스케일.
class _PathPainter extends CustomPainter {
  _PathPainter({required this.pawOpacities});
  final List<double> pawOpacities;

  @override
  void paint(Canvas canvas, Size size) {
    final kx = size.width / 340, ky = size.height / 250;
    final path = Path()
      ..moveTo(120 * kx, 250 * ky)
      ..cubicTo(180 * kx, 205 * ky, 95 * kx, 160 * ky, 150 * kx, 125 * ky)
      ..cubicTo(190 * kx, 100 * ky, 215 * kx, 92 * ky, 212 * kx, 66 * ky)
      ..lineTo(232 * kx, 66 * ky)
      ..cubicTo(238 * kx, 100 * ky, 196 * kx, 116 * ky, 178 * kx, 142 * ky)
      ..cubicTo(152 * kx, 178 * ky, 235 * kx, 210 * ky, 185 * kx, 250 * ky)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFF3E3C6));

    // 발자국: (x, y, rotationDeg, scale) — 2b 좌표
    const paws = [
      (148.0, 196.0, -14.0, .5),
      (148.0, 162.0, 8.0, .46),
      (176.0, 120.0, -6.0, .42),
      (204.0, 84.0, 2.0, .38),
    ];
    for (var i = 0; i < paws.length; i++) {
      final (x, y, deg, s) = paws[i];
      final op = pawOpacities[i];
      if (op <= 0) continue;
      canvas.save();
      canvas.translate(x * kx, y * ky);
      canvas.rotate(deg * 3.14159 / 180);
      canvas.scale(s * kx);
      _drawPaw(canvas,
          Paint()..color = const Color(0xFF6B4632).withValues(alpha: op));
      canvas.restore();
    }
  }

  void _drawPaw(Canvas c, Paint p) {
    c.drawOval(
        Rect.fromCenter(center: const Offset(7, 8), width: 4.4, height: 6), p);
    c.drawOval(
        Rect.fromCenter(center: const Offset(12, 6), width: 4.4, height: 6), p);
    c.drawOval(
        Rect.fromCenter(center: const Offset(17, 8), width: 4.4, height: 6), p);
    final pad = Path()
      ..moveTo(12, 11)
      ..cubicTo(8.5, 11, 6, 13.6, 6, 16.2)
      ..cubicTo(6, 18.1, 7.5, 19.2, 9.2, 18.8)
      ..cubicTo(10.2, 18.6, 11, 18.4, 12, 18.4)
      ..cubicTo(13, 18.4, 13.8, 18.6, 14.8, 18.8)
      ..cubicTo(16.5, 19.2, 18, 18.1, 18, 16.2)
      ..cubicTo(18, 13.6, 15.5, 11, 12, 11)
      ..close();
    c.drawPath(pad, p);
  }

  @override
  bool shouldRepaint(_PathPainter old) => old.pawOpacities != pawOpacities;
}
