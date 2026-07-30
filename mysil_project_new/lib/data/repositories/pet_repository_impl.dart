import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_exception.dart';
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
      idempotencyKey: 'create-pet-$name',
    );
    final pet = PetModel.fromJson(Json.asMap(data));
    await _cache.savePetId(pet.id);
    return pet;
  }

  @override
  Future<Pet> getPet(int petId) async {
    final data = await _client.get(ApiEndpoints.pet(petId));
    return PetModel.fromJson(Json.asMap(data));
  }

  @override
  Future<Pet> updatePet({
    required int petId,
    String? name,
    String? profileImage,
  }) async {
    final data = await _client.patch(
      ApiEndpoints.pet(petId),
      data: {
        if (name != null) 'name': name,
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
        : Json.asMapList(Json.asMap(data)['items'] ?? Json.asMap(data)['history']);
    return list
        .map(AffinityHistoryEntryModel.fromJson)
        .toList(growable: false);
  }

  @override
  Future<Pet?> getCurrentPet() async {
    final petId = await _cache.readPetId();
    if (petId == null) return null;
    try {
      return await getPet(petId);
    } on ApiException catch (e) {
      // 삭제된 펫이면 캐시를 비운다.
      if (e.code == ApiErrorCode.petNotFound || e.isNotFound) return null;
      rethrow;
    }
  }

  @override
  Future<void> setCurrentPet(int petId) => _cache.savePetId(petId);
}
