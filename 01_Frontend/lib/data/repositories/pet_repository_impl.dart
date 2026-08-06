import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/config/api_config.dart';
import '../../core/storage/session_cache.dart';
import '../../core/utils/json_parse.dart';
import '../../domain/entities/pet.dart';
import '../../domain/repositories/pet_repository.dart';
import '../models/pet_model.dart';

class PetRepositoryImpl implements PetRepository {
  PetRepositoryImpl({
    required ApiClient client,
    required SessionCache sessionCache,
  })  : _client = client,
        _cache = sessionCache;

  final ApiClient _client;
  final SessionCache _cache;

  @override
  Future<Pet> createPet({required String name, String? profileImage}) async {
    final data = await _client.post(
      ApiEndpoints.pets,
      data: {'name': name, 'profileImage': profileImage},
      // **이름으로 키를 만들면 안 된다.** 서버는 같은 멱등키를 "이미 처리한
      // 요청"으로 보고 기존 펫을 그대로 돌려준다(pet_creation_requests).
      // 그래서 이름이 같은 펫을 두 마리 만들 수 없고, 사용자에게는 "추가가
      // 안 된다"로 보인다. 2026-08-04 에 실제로 겪었다.
      //
      // 멱등키가 묶어야 하는 것은 **같은 요청의 재시도**다. 사용자가 `추가` 를
      // 누르는 행위 하나가 곧 하나의 요청이므로, 호출마다 새 키를 만든다.
      // (dio 가 네트워크 오류로 재시도할 때는 같은 Options 를 재사용하므로
      //  같은 키가 나가고, 그때는 중복 생성이 제대로 막힌다)
      idempotencyKey: 'create-pet-${_freshRequestId()}',
    );
    final pet = PetModel.fromJson(Json.asMap(data));
    await _cache.savePetId(pet.id);
    return pet;
  }

  /// 요청 하나를 구분하는 값. 서버 패턴(`^[A-Za-z0-9._:-]+$`)에 맞는 문자만 쓴다.
  String _freshRequestId() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    // 같은 마이크로초에 두 번 불릴 경우까지 대비해 순번을 덧붙인다.
    _requestSeq += 1;
    return '$micros-$_requestSeq';
  }

  int _requestSeq = 0;

  @override
  Future<List<Pet>> getPets() async {
    final ids = await _cache.readKnownPetIds();
    if (ids.isEmpty) return const [];

    final pets = <Pet>[];
    for (final id in ids) {
      try {
        pets.add(await getPet(id));
      } on ApiException catch (e) {
        // 이미 지워진 펫이면 목록에서 뺀다. 그러지 않으면 매번 404 를 부른다.
        if (e.code == ApiErrorCode.petNotFound || e.isNotFound) {
          await _cache.forgetPetId(id);
          continue;
        }
        // 그 밖의 오류(네트워크 등)는 이 펫만 건너뛴다. 한 마리를 못 받았다고
        // 목록 전체를 실패로 만들지 않는다.
        continue;
      }
    }
    return pets;
  }

  @override
  Future<Pet> getPet(int petId) async {
    final data = await _client.get(ApiEndpoints.pet(petId));
    return PetModel.fromJson(Json.asMap(data));
  }

  @override
  Future<Pet> updatePet({
    required int petId,
    required String name,
    String? profileImage,
  }) async {
    final data = await _client.patch(
      ApiEndpoints.pet(petId),
      // name 은 서버에서 required 다. 조건부로 빼면 사진만 바꿀 때 400 이 난다.
      data: {
        'name': name,
        if (profileImage != null) 'profileImage': profileImage,
      },
    );
    return PetModel.fromJson(Json.asMap(data));
  }

  @override
  Future<Affinity> getAffinity(int petId) async {
    final data = await _client.get(ApiEndpoints.petAffinity(petId));
    return AffinityModel.fromJson(Json.asMap(data));
  }

  @override
  Future<List<AffinityHistoryEntry>> getAffinityHistory(
    int petId, {
    int? limit,
  }) async {
    final data = await _client.get(
      ApiEndpoints.petAffinityHistory(petId),
      query: {if (limit != null) 'limit': limit},
    );

    // 명세서에 응답 예시가 없어 배열/{items:[]} 두 형태를 모두 받아준다.
    final list = data is List
        ? Json.asMapList(data)
        : Json.asMapList(
            Json.asMap(data)['items'] ?? Json.asMap(data)['history']);
    return list.map(AffinityHistoryEntryModel.fromJson).toList(growable: false);
  }

  @override
  Future<Pet?> getCurrentPet() async {
    var petId = await _cache.readPetId();
    // 로컬 테스트 로그인은 펫 생성 과정을 거치지 않아 캐시에 id가 없을 수 있다.
    // 운영/개발 서버에는 절대 적용하지 않고 loopback 백엔드에서만 시드 펫을 쓴다.
    petId ??= ApiConfig.isLoopback ? ApiConfig.localTestPetId : null;
    if (petId == null) return null;
    try {
      final pet = await getPet(petId);
      // 백엔드의 로컬 fallback이 다른 시드 id를 돌려준 경우에도 다음 조회부터는
      // 실제 id를 사용하도록 캐시를 바로잡는다.
      await _cache.savePetId(pet.id);
      return pet;
    } on ApiException catch (e) {
      // 삭제된 펫이면 캐시를 비운다.
      if (e.code == ApiErrorCode.petNotFound || e.isNotFound) return null;
      rethrow;
    }
  }

  @override
  Future<void> setCurrentPet(int petId) => _cache.savePetId(petId);
}
