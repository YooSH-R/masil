import 'dart:async';

import '../../domain/entities/pet.dart';
import '../../domain/repositories/pet_repository.dart';
import 'base_view_model.dart';

class PetViewModel extends BaseViewModel {
  PetViewModel(this._petRepository);

  final PetRepository _petRepository;

  Pet? _pet;
  Affinity? _affinity;
  bool _hasLoadedCurrentPet = false;
  List<AffinityHistoryEntry> _affinityHistory = const [];

  Pet? get pet => _pet;
  bool get hasLoadedCurrentPet => _hasLoadedCurrentPet;
  bool get requiresDevicePairing => _hasLoadedCurrentPet && _pet?.robot == null;
  int? get petId => _pet?.id;
  String get petName => _pet?.name ?? '마실이';
  Affinity? get affinity => _affinity ?? _pet?.affinity;
  List<AffinityHistoryEntry> get affinityHistory => _affinityHistory;

  /// 이 앱이 아는 펫 전부. 목록 화면이 그린다.
  List<Pet> _pets = const [];
  List<Pet> get pets => _pets;

  /// GET /pets로 로그인 사용자의 실제 펫 목록을 불러온다.
  /// 목록을 불러오면 현재 펫도 그 안의 것으로 맞춰 둔다.
  Future<void> loadPets({bool silent = true}) async {
    final pets = await guard(() => _petRepository.getPets(), silent: silent);
    if (pets == null) return;

    _pets = pets;
    // 현재 펫이 비어 있거나 목록에서 사라졌으면 첫 마리로 맞춘다.
    if (_pet == null || !pets.any((p) => p.id == _pet!.id)) {
      _pet = pets.isEmpty ? null : pets.first;
      _affinity = _pet?.affinity;
    }
    safeNotify();
  }

  /// 홈 화면 진입 시 호출. 캐시된 petId로 프로필 + 친밀도를 함께 불러온다.
  Future<void> loadCurrentPet({bool silent = false}) async {
    final pet = await guard<Pet?>(
      () => _petRepository.getCurrentPet(),
      silent: silent,
    );
    _hasLoadedCurrentPet = true;
    if (pet == null) {
      // 조회는 정상적으로 끝났지만 펫이 없으면 이전 세션의 화면 값을 남기지 않는다.
      if (!hasError) {
        _pet = null;
        _affinity = null;
      }
      safeNotify();
      return;
    }

    _pet = pet;
    _affinity = pet.affinity;
    safeNotify();
  }

  /// GET /pets/{petId}/affinity — 친밀도만 갱신.
  Future<void> refreshAffinity({bool silent = true}) async {
    final id = _pet?.id;
    if (id == null) return;

    final affinity = await guard(
      () => _petRepository.getAffinity(id),
      silent: silent,
    );
    if (affinity == null) return;

    _applyAffinity(affinity);
  }

  // --- 친밀도 실시간 수신 (SSE) ---
  //
  // GET 은 최초값과 재연결 시 동기화에, SSE 는 연결된 동안의 변경 수신에
  // 쓴다. 둘 중 하나만으로는 부족하다. GET 만 쓰면 실시간이 아니고, SSE 만
  // 쓰면 끊겨 있던 동안의 변경을 놓친다.

  StreamSubscription<Affinity>? _affinitySubscription;
  Timer? _affinityReconnectTimer;
  int _affinityRetry = 0;

  /// 연결을 유지해야 하는 상태인지. 앱이 백그라운드로 가거나 로그아웃하면
  /// false 가 되고, 그 뒤에 도착하는 콜백은 재연결을 예약하지 않는다.
  bool _affinityStreamWanted = false;

  /// 구독 중인 펫. 펫이 바뀌면 이 값과 달라져 다시 연결한다.
  int? _affinityStreamPetId;

  static const Duration _affinityRetryBase = Duration(seconds: 5);
  static const Duration _affinityRetryMax = Duration(seconds: 60);

  /// 서버가 30분마다 연결을 정상 종료한다(`pet.affinity.sse.timeout-ms`).
  /// 오류가 아니라 예정된 동작이므로 곧바로 다시 붙는다.
  static const Duration _affinityRenewDelay = Duration(seconds: 1);

  bool get isAffinityStreaming => _affinitySubscription != null;

  /// 친밀도 구독을 시작한다. 이미 같은 펫을 구독 중이면 아무것도 하지 않는다.
  Future<void> startAffinityStream() async {
    final id = _pet?.id;
    if (id == null) return;
    if (_affinityStreamWanted &&
        _affinityStreamPetId == id &&
        _affinitySubscription != null) {
      return;
    }

    _affinityStreamWanted = true;
    _affinityStreamPetId = id;
    await _connectAffinityStream(id);
  }

  /// 구독을 끊는다. 앱이 백그라운드로 갈 때·로그아웃할 때·펫이 바뀔 때 부른다.
  Future<void> stopAffinityStream() async {
    _affinityStreamWanted = false;
    _affinityStreamPetId = null;
    _affinityRetry = 0;
    _affinityReconnectTimer?.cancel();
    _affinityReconnectTimer = null;

    final subscription = _affinitySubscription;
    _affinitySubscription = null;
    await subscription?.cancel();
  }

  Future<void> _connectAffinityStream(int petId) async {
    final previous = _affinitySubscription;
    _affinitySubscription = null;
    await previous?.cancel();

    if (!_affinityStreamWanted || _pet?.id != petId) return;

    // 붙기 전에 일반 GET 으로 값을 맞춘다. 끊겨 있던 동안의 변경은 SSE 로
    // 오지 않기 때문이다.
    await refreshAffinity();
    if (!_affinityStreamWanted || _pet?.id != petId) return;

    _affinitySubscription = _petRepository.streamAffinity(petId).listen(
      (affinity) {
        // 한 번이라도 받았으면 연결이 건강하다는 뜻이라 백오프를 되돌린다.
        _affinityRetry = 0;
        _applyAffinity(affinity);
      },
      onError: (_) => _scheduleAffinityReconnect(petId, failed: true),
      onDone: () => _scheduleAffinityReconnect(petId, failed: false),
      cancelOnError: true,
    );
  }

  void _scheduleAffinityReconnect(int petId, {required bool failed}) {
    _affinitySubscription = null;
    if (!_affinityStreamWanted || _pet?.id != petId) return;

    final delay = failed ? _affinityBackoff(_affinityRetry++) : _affinityRenewDelay;
    _affinityReconnectTimer?.cancel();
    _affinityReconnectTimer = Timer(delay, () {
      if (!_affinityStreamWanted || _pet?.id != petId) return;
      _connectAffinityStream(petId);
    });
  }

  /// 5초에서 시작해 60초까지 늘린다. 서버가 죽어 있을 때 재연결이 몰리지
  /// 않게 하려는 것이다.
  Duration _affinityBackoff(int attempt) {
    final seconds = _affinityRetryBase.inSeconds << attempt.clamp(0, 4);
    return Duration(
      seconds: seconds > _affinityRetryMax.inSeconds
          ? _affinityRetryMax.inSeconds
          : seconds,
    );
  }

  void _applyAffinity(Affinity incoming) {
    if (!_isNewerAffinity(incoming)) return;
    _affinity = incoming;
    safeNotify();
  }

  /// 들어온 값이 지금 값보다 새 것인지.
  ///
  /// GET 응답과 SSE 이벤트가 같은 [_affinity] 를 쓴다. 네트워크는 순서를
  /// 보장하지 않아서, 느린 GET 응답이 최신 SSE 값보다 늦게 도착해 덮어쓰면
  /// **점수가 눈에 보이게 거꾸로 간다.** 그걸 막는 가드다.
  bool _isNewerAffinity(Affinity incoming) {
    final currentAt = affinity?.updatedAt;
    final incomingAt = incoming.updatedAt;

    // 시각이 없는 값은 최신임을 증명할 수 없다. 이미 시각이 있는 값을 갖고
    // 있으면 덮어쓰지 않는다(펫 프로필 응답의 친밀도에는 updatedAt 이 없다).
    if (incomingAt == null) return currentAt == null;
    if (currentAt == null) return true;

    // 같은 시각은 반영한다. 같은 밀리초에 두 번 바뀌었을 때 뒤 값을 버리면
    // 화면이 낡은 채로 남는다.
    return !incomingAt.isBefore(currentAt);
  }

  @override
  void dispose() {
    _affinityReconnectTimer?.cancel();
    _affinitySubscription?.cancel();
    super.dispose();
  }

  /// GET /pets/{petId}/affinity/history
  ///
  /// 이 엔드포인트는 아직 배포되지 않았다(2026-08-03 확인). 미배포 경로는 401 +
  /// 빈 본문으로 오므로 기본값을 silent 로 둔다. 그러지 않으면 친밀도 화면에
  /// 들어가기만 해도 "토큰 인증 실패" 같은 오류가 뜬다.
  /// 배포되면 이 주석만 지우면 된다.
  Future<void> loadAffinityHistory({int limit = 30, bool silent = true}) async {
    final id = _pet?.id;
    if (id == null) return;

    final history = await guard(
      () => _petRepository.getAffinityHistory(id, limit: limit),
      silent: silent,
    );
    if (history == null) return;

    _affinityHistory = history;
    safeNotify();
  }

  /// POST /pets — 펫 생성 후 기준 펫으로 등록.
  Future<bool> createPet({required String name, String? profileImage}) async {
    final pet = await guard(
      () => _petRepository.createPet(name: name, profileImage: profileImage),
    );
    if (pet == null) return false;

    _pet = pet;
    _affinity = pet.affinity;
    // 새로 만든 펫을 목록에도 즉시 더한다. 목록을 다시 불러오지 않아도
    // 화면에 바로 보이게 하려는 것이다(리포지토리가 id 는 이미 저장했다).
    if (!_pets.any((p) => p.id == pet.id)) {
      _pets = [..._pets, pet];
    }
    safeNotify();
    return true;
  }

  /// PATCH /pets/{petId} — 이름·프로필 수정.
  ///
  /// [name] 을 넘기지 않으면 지금 이름을 그대로 보낸다. 서버가 name 을 필수로
  /// 받기 때문에, 사진만 바꾸는 화면에서도 이름이 빠지면 400 이 난다.
  Future<bool> updatePet({
    String? name,
    String? profileImage,
    int? dailyWalkCount,
  }) async {
    final current = _pet;
    final id = current?.id;
    if (current == null || id == null) return false;

    final pet = await guard(() => _petRepository.updatePet(
          petId: id,
          name: name ?? current.name,
          profileImage: profileImage,
          dailyWalkCount: dailyWalkCount,
        ));
    if (pet == null) return false;

    _pet = pet;
    safeNotify();
    return true;
  }

  Future<bool> deletePet(int petId) async {
    await guard<void>(() => _petRepository.deletePet(petId));
    if (hasError) return false;

    _pets = _pets.where((pet) => pet.id != petId).toList(growable: false);
    if (_pet?.id == petId) {
      _pet = _pets.isEmpty ? null : _pets.first;
    }
    _affinity = _pet?.affinity;
    _affinityHistory = const [];
    _hasLoadedCurrentPet = true;
    if (_pet != null) {
      await _petRepository.setCurrentPet(_pet!.id);
    }
    safeNotify();
    return true;
  }

  Future<void> selectPet(int id) async {
    await _petRepository.setCurrentPet(id);
    await loadCurrentPet();
  }
}
