import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/auth_view_model.dart';
import '../viewmodels/pet_view_model.dart';

/// 친밀도 SSE 연결을 **로그인 세션 단위**로 관리한다.
///
/// 화면마다 연결하면 홈과 친밀도 화면이 각각 소켓을 열어 커넥션이 두 배가
/// 되고, 화면을 옮길 때마다 끊겼다 붙는다. 여기서 한 번만 붙여두면 두 화면이
/// 같은 [PetViewModel] 을 보고 있으니 동시에 갱신된다.
///
/// 붙이고 끊는 기준:
/// - 로그인 + 펫이 정해짐 → 연결
/// - 로그아웃 · 펫 없음 → 끊기
/// - 펫이 바뀜 → 새 펫으로 다시 연결
/// - 앱이 백그라운드로 감 → 끊기 (소켓·배터리를 붙들고 있을 이유가 없다)
/// - 앱 복귀 → 일반 GET 으로 값을 맞춘 뒤 다시 연결
class AffinityStreamBinder extends StatefulWidget {
  const AffinityStreamBinder({super.key, required this.child});

  final Widget child;

  @override
  State<AffinityStreamBinder> createState() => _AffinityStreamBinderState();
}

class _AffinityStreamBinderState extends State<AffinityStreamBinder>
    with WidgetsBindingObserver {
  /// 앱이 백그라운드에 있는 동안에는 펫이 정해져도 붙이지 않는다.
  bool _isForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _isForeground) return;
    _isForeground = foreground;

    final petVm = context.read<PetViewModel>();
    if (!foreground) {
      petVm.stopAffinityStream();
      return;
    }
    // 재연결 직전 값 동기화는 startAffinityStream 안에서 GET 으로 한다.
    _syncConnection(context.read<AuthViewModel>(), petVm);
  }

  void _syncConnection(AuthViewModel authVm, PetViewModel petVm) {
    if (!_isForeground || !authVm.isAuthenticated || petVm.petId == null) {
      petVm.stopAffinityStream();
      return;
    }
    petVm.startAffinityStream();
  }

  @override
  Widget build(BuildContext context) {
    // 로그인 상태와 펫이 바뀔 때마다 연결을 맞춘다. watch 로 보되 실제 작업은
    // 프레임이 끝난 뒤에 한다 — build 도중에 notifyListeners 가 불리면
    // "setState during build" 로 터진다.
    final authVm = context.watch<AuthViewModel>();
    final petVm = context.watch<PetViewModel>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncConnection(authVm, petVm);
    });

    return widget.child;
  }
}
