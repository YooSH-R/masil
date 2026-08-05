import '../../domain/entities/pet.dart';
import '../../domain/repositories/pet_repository.dart';
import 'base_view_model.dart';

class PetViewModel extends BaseViewModel {
  PetViewModel(this._petRepository);

  final PetRepository _petRepository;

  Pet? _pet;
  Affinity? _affinity;
  List<AffinityHistoryEntry> _affinityHistory = const [];

  Pet? get pet => _pet;
  int? get petId => _pet?.id;
  String get petName => _pet?.name ?? '마실이';
  Affinity? get affinity => _affinity ?? _pet?.affinity;
  List<AffinityHistoryEntry> get affinityHistory => _affinityHistory;

  /// 이 앱이 아는 펫 전부. 목록 화면이 그린다.
  List<Pet> _pets = const [];
  List<Pet> get pets => _pets;

  /// GET /pets/{petId} 를 아는 id 마다 호출해 목록을 만든다.
  ///
  /// 서버에 목록 API 가 없어서 이렇게 모은다([PetRepository.getPets] 참고).
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
    if (pet == null) return;

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

    _affinity = affinity;
    safeNotify();
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
  Future<bool> updatePet({String? name, String? profileImage}) async {
    final current = _pet;
    final id = current?.id;
    if (current == null || id == null) return false;

    final pet = await guard(() => _petRepository.updatePet(
          petId: id,
          name: name ?? current.name,
          profileImage: profileImage,
        ));
    if (pet == null) return false;

    _pet = pet;
    safeNotify();
    return true;
  }

  Future<void> selectPet(int id) async {
    await _petRepository.setCurrentPet(id);
    await loadCurrentPet();
  }
}
