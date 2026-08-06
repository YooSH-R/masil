import '../entities/pet.dart';

/// 명세서 2.2 펫 + 2.3 친밀도 API.
/// (친밀도 경로가 /pets/{petId} 아래에 있어 같은 리포지토리에서 다룬다)
abstract class PetRepository {
  /// POST /pets — 펫 생성
  Future<Pet> createPet({required String name, String? profileImage});

  /// 이 앱이 아는 펫 전부.
  ///
  /// `GET /pets`로 로그인 사용자의 실제 펫을 조회한다. 구버전 서버에서는
  /// 만들 때 저장해 둔 id를 하나씩 조회하는 방식으로 호환한다.
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

  /// 마지막으로 사용한 펫. 캐시가 없으면 서버의 내 펫 목록에서 복구한다.
  Future<Pet?> getCurrentPet();

  /// 이후 화면에서 쓸 기준 펫 지정.
  Future<void> setCurrentPet(int petId);
}
