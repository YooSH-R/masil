import '../entities/pet.dart';

/// 명세서 2.2 펫 + 2.3 친밀도 API.
/// (친밀도 경로가 /pets/{petId} 아래에 있어 같은 리포지토리에서 다룬다)
abstract class PetRepository {
  /// POST /pets — 펫 생성
  Future<Pet> createPet({required String name, String? profileImage});

  /// 이 앱이 아는 펫 전부.
  ///
  /// 서버에 `GET /pets` 가 없어서, 만들 때 저장해 둔 id 를 하나씩
  /// `GET /pets/{petId}` 로 조회해 모은다. 이미 삭제된 펫(404)은 목록에서
  /// 빼고 건너뛴다.
  Future<List<Pet>> getPets();

  /// GET /pets/{petId} — 펫 프로필 조회
  Future<Pet> getPet(int petId);

  /// PATCH /pets/{petId} — 펫 정보 수정
  /// PATCH /pets/{petId} — 펫 정보 수정
  ///
  /// [name] 은 서버 `UpdatePetRequest` 에서 **required** 다. 사진만 바꾸는
  /// 경우에도 현재 이름을 그대로 실어 보내야 한다(빼면 400). 그래서 여기서도
  /// 필수로 둔다 — 호출하는 쪽이 빠뜨리면 컴파일 단계에서 걸린다.
  Future<Pet> updatePet({
    required int petId,
    required String name,
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
