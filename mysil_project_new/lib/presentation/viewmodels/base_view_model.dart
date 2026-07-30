import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../core/network/api_exception.dart';

/// 로딩·오류 상태 처리를 한 곳에 모은 베이스.
/// 화면은 isLoading / errorMessage / error.isRetriable 만 보면 된다.
abstract class BaseViewModel extends ChangeNotifier {
  bool _isLoading = false;
  ApiException? _error;
  bool _disposed = false;

  bool get isLoading => _isLoading;
  ApiException? get error => _error;
  String? get errorMessage => _error?.message;
  bool get hasError => _error != null;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// dispose 이후 notifyListeners 호출로 터지는 것을 막는다.
  ///
  /// 빌드 도중(initState/build에서 시작된 호출)에 notifyListeners를 부르면
  /// "setState() or markNeedsBuild() called during build" 예외가 나므로
  /// 그런 경우에는 프레임이 끝난 뒤로 미뤄서 알린다.
  void safeNotify() {
    if (_disposed) return;

    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      binding.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
      return;
    }
    notifyListeners();
  }

  /// API 호출 공통 래퍼. 실패하면 null을 돌려주고 error에 담는다.
  /// [silent]가 true면 로딩 표시 없이 조용히 갱신한다(폴링·백그라운드 갱신용).
  Future<T?> guard<T>(
    Future<T> Function() action, {
    bool silent = false,
  }) async {
    _error = null;
    if (!silent) {
      _isLoading = true;
      safeNotify();
    }

    try {
      return await action();
    } on ApiException catch (e) {
      _error = e;
      return null;
    } catch (e) {
      _error = ApiException(
        code: ApiErrorCode.unknown,
        message: '처리 중 문제가 발생했어요. 다시 시도해 주세요.',
      );
      debugPrint('Unhandled error in ${runtimeType.toString()}: $e');
      return null;
    } finally {
      _isLoading = false;
      safeNotify();
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    safeNotify();
  }
}
