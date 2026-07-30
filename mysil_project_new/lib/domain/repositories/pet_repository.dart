import '../entities/pet.dart';

/// 명세서 2.2 펫 + 2.3 친밀도 API.
/// (친밀도 경로가 /pets/{petId} 아래에 있어 같은 리포지토리에서 다룬다)
abstract class PetRepository {
  /// POST /pets — 펫 생성
  Future<Pet> createPet({required String name, String? profileImage});

  /// GET /pets/{petId} — 펫 프로필 조회
  Future<Pet> getPet(int petId);

  /// PATCH /pets/{petId} — 펫 정보 수정
  Future<Pet> updatePet({
    required int petId,
    String? name,
    String? profileImage,
  });

  /// GET /pets/{petId}/affinity — 친밀도·기분 조회
  Future<Affinity> getAffinity(int petId);

  /// GET /pets/{petId}/affinity/history — 친밀도 변화 이력
  Future<List<AffinityHistoryEntry>> getAffinityHistory(int petId, {int? limit});

  /// 마지막으로 사용한 펫. 목록 조회 API가 없어 로컬 캐시의 petId로 조회한다.
  Future<Pet?> getCurrentPet();

  /// 이후 화면에서 쓸 기준 펫 지정.
  Future<void> setCurrentPet(int petId);
}
