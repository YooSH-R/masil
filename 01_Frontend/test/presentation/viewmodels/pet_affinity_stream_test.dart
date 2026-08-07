import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mysil_project_new/domain/entities/pet.dart';
import 'package:mysil_project_new/domain/repositories/pet_repository.dart';
import 'package:mysil_project_new/presentation/viewmodels/pet_view_model.dart';

Affinity _affinity(int score, {DateTime? updatedAt}) => Affinity(
      score: score,
      level: 1,
      mood: PetMood.calm,
      updatedAt: updatedAt,
    );

Pet _pet() => const Pet(
      id: 7,
      name: '마실',
      robot: PairedRobotSummary(robotId: 1, online: true, batteryLevel: 80),
    );

/// 필요한 것만 구현한 가짜 저장소. GET 응답 시점과 SSE 방출 시점을 테스트가
/// 직접 정할 수 있어야 경합을 재현할 수 있다.
class _FakePetRepository implements PetRepository {
  _FakePetRepository({required this.affinityOnGet});

  /// GET 이 돌려줄 값. 완료 시점을 테스트가 잡으려면 Completer 를 쓴다.
  Future<Affinity> Function() affinityOnGet;

  final StreamController<Affinity> streamed =
      StreamController<Affinity>.broadcast();
  int streamCallCount = 0;

  @override
  Future<Affinity> getAffinity(int petId) => affinityOnGet();

  @override
  Stream<Affinity> streamAffinity(int petId) {
    streamCallCount++;
    return streamed.stream;
  }

  @override
  Future<Pet?> getCurrentPet() async => _pet();

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 은 이 테스트에서 안 쓴다');
}

/// `_pet` 을 채우기 위한 최소 경로. loadCurrentPet 이 getCurrentPet 을 쓴다.
Future<PetViewModel> _viewModelWithPet(_FakePetRepository repository) async {
  final vm = PetViewModel(repository);
  await vm.loadCurrentPet();
  return vm;
}

void main() {
  // BaseViewModel.safeNotify 가 SchedulerBinding 을 본다.
  TestWidgetsFlutterBinding.ensureInitialized();

  final older = DateTime.utc(2026, 8, 7, 10, 0, 0);
  final newer = DateTime.utc(2026, 8, 7, 10, 0, 5);

  group('updatedAt 가드', () {
    test('더 새로운 값은 반영한다', () async {
      final repo = _FakePetRepository(
        affinityOnGet: () async => _affinity(10, updatedAt: older),
      );
      final vm = await _viewModelWithPet(repo);

      await vm.refreshAffinity();
      expect(vm.affinity?.score, 10);

      await vm.startAffinityStream();
      repo.streamed.add(_affinity(20, updatedAt: newer));
      await Future<void>.delayed(Duration.zero);

      expect(vm.affinity?.score, 20);
      await vm.stopAffinityStream();
    });

    // 이 테스트가 이 기능의 핵심이다. 느린 GET 응답이 최신 SSE 값보다 늦게
    // 도착해도 점수가 거꾸로 가지 않아야 한다.
    test('늦게 도착한 낡은 GET 응답은 최신 SSE 값을 덮어쓰지 않는다', () async {
      final slowGet = Completer<Affinity>();
      var getCalls = 0;
      final repo = _FakePetRepository(affinityOnGet: () {
        getCalls++;
        // 첫 GET(화면 진입)은 응답이 늦고, 두 번째(스트림 연결 전 동기화)는
        // 곧바로 응답한다. 실제로 두 요청이 겹치는 상황이 이렇다.
        return getCalls == 1
            ? slowGet.future
            : Future.value(_affinity(60, updatedAt: older));
      });
      final vm = await _viewModelWithPet(repo);

      // 화면 진입 GET 을 띄워두고 아직 응답하지 않는다.
      final pending = vm.refreshAffinity();

      // 그 사이 연결이 붙고 SSE 로 최신값이 먼저 도착한다.
      await vm.startAffinityStream();
      repo.streamed.add(_affinity(90, updatedAt: newer));
      await Future<void>.delayed(Duration.zero);
      expect(vm.affinity?.score, 90);

      // 이제서야 낡은 GET 응답이 도착한다.
      slowGet.complete(_affinity(50, updatedAt: older));
      await pending;

      expect(vm.affinity?.score, 90, reason: '낡은 값이 최신값을 덮어썼다');
      await vm.stopAffinityStream();
    });

    test('같은 시각이면 반영한다', () async {
      final repo = _FakePetRepository(
        affinityOnGet: () async => _affinity(10, updatedAt: older),
      );
      final vm = await _viewModelWithPet(repo);
      await vm.refreshAffinity();

      await vm.startAffinityStream();
      repo.streamed.add(_affinity(11, updatedAt: older));
      await Future<void>.delayed(Duration.zero);

      expect(vm.affinity?.score, 11);
      await vm.stopAffinityStream();
    });

    // 펫 프로필 응답의 친밀도에는 updatedAt 이 없다. 그걸로 시각이 있는
    // 최신값을 덮어쓰면 SSE 로 받은 값이 사라진다.
    test('updatedAt 이 없는 값은 시각이 있는 값을 덮어쓰지 않는다', () async {
      final repo = _FakePetRepository(
        affinityOnGet: () async => _affinity(70, updatedAt: newer),
      );
      final vm = await _viewModelWithPet(repo);
      await vm.refreshAffinity();
      expect(vm.affinity?.score, 70);

      await vm.startAffinityStream();
      repo.streamed.add(_affinity(1));
      await Future<void>.delayed(Duration.zero);

      expect(vm.affinity?.score, 70);
      await vm.stopAffinityStream();
    });
  });

  group('연결 관리', () {
    test('start 는 GET 으로 값을 맞춘 뒤 붙는다', () async {
      var getCalls = 0;
      final repo = _FakePetRepository(affinityOnGet: () async {
        getCalls++;
        return _affinity(10, updatedAt: older);
      });
      final vm = await _viewModelWithPet(repo);

      await vm.startAffinityStream();

      expect(getCalls, 1, reason: '재연결 전 동기화 GET 이 없었다');
      expect(repo.streamCallCount, 1);
      expect(vm.isAffinityStreaming, isTrue);
      await vm.stopAffinityStream();
    });

    test('이미 같은 펫을 구독 중이면 다시 붙지 않는다', () async {
      final repo = _FakePetRepository(
        affinityOnGet: () async => _affinity(10, updatedAt: older),
      );
      final vm = await _viewModelWithPet(repo);

      await vm.startAffinityStream();
      await vm.startAffinityStream();

      expect(repo.streamCallCount, 1);
      await vm.stopAffinityStream();
    });

    test('stop 하면 구독이 끊기고 이후 이벤트는 무시된다', () async {
      final repo = _FakePetRepository(
        affinityOnGet: () async => _affinity(10, updatedAt: older),
      );
      final vm = await _viewModelWithPet(repo);
      await vm.startAffinityStream();

      await vm.stopAffinityStream();
      expect(vm.isAffinityStreaming, isFalse);

      repo.streamed.add(_affinity(99, updatedAt: newer));
      await Future<void>.delayed(Duration.zero);

      expect(vm.affinity?.score, 10);
    });
  });
}
