import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysil_project_new/core/network/api_client.dart';
import 'package:mysil_project_new/core/network/api_exception.dart';
import 'package:mysil_project_new/core/storage/session_cache.dart';
import 'package:mysil_project_new/data/repositories/pet_repository_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// 연결이 성립되지 않는 주소. 예약 포트 9(discard)로 곧바로 거절된다.
  PetRepositoryImpl unreachableRepository() => PetRepositoryImpl(
        client: ApiClient(Dio(BaseOptions(
          baseUrl: 'http://127.0.0.1:9/',
          connectTimeout: const Duration(milliseconds: 300),
        ))),
        sessionCache: SessionCache(),
      );

  // 리뷰에서 "eventStream 을 await 하는 최초 단계의 예외가 listen 을 걸기도
  // 전에 밖으로 던져진다" 는 지적이 있었다. streamAffinity 는 async* 라 본문이
  // 구독 시점에 실행되고, 본문에서 던진 예외는 스트림의 에러로 전달된다.
  // 그래서 onError 로 들어오고 재연결 로직이 정상 동작한다. 이 테스트가 그
  // 계약을 고정한다.
  test('연결 수립 실패는 스트림 에러로 전달된다 (호출부로 던져지지 않는다)', () async {
    final repository = unreachableRepository();

    // 스트림을 만드는 것만으로는 아무 일도 일어나지 않는다 — 여기서 예외가
    // 던져지면 이 줄에서 테스트가 깨진다.
    final stream = repository.streamAffinity(1);

    await expectLater(stream, emitsError(isA<ApiException>()));
  });

  test('listen 의 onError 로 들어온다', () async {
    final repository = unreachableRepository();
    Object? received;

    final subscription = repository.streamAffinity(1).listen(
      (_) {},
      onError: (Object error) => received = error,
      cancelOnError: true,
    );

    // 연결 시도가 끝날 시간을 준다.
    await Future<void>.delayed(const Duration(seconds: 2));
    await subscription.cancel();

    expect(received, isA<ApiException>());
  });
}
