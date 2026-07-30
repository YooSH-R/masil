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
  Future<void> loadAffinityHistory({int limit = 30}) async {
    final id = _pet?.id;
    if (id == null) return;

    final history = await guard(
      () => _petRepository.getAffinityHistory(id, limit: limit),
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
    safeNotify();
    return true;
  }

  /// PATCH /pets/{petId} — 이름·프로필 수정.
  Future<bool> updatePet({String? name, String? profileImage}) async {
    final id = _pet?.id;
    if (id == null) return false;

    final pet = await guard(() => _petRepository.updatePet(
          petId: id,
          name: name,
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
