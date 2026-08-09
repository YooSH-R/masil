import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/json_parse.dart';
import '../../domain/entities/walk.dart';
import '../../domain/entities/walk_diary.dart';
import '../../domain/repositories/walk_repository.dart';
import '../models/walk_diary_model.dart';
import '../models/walk_model.dart';

class WalkRepositoryImpl implements WalkRepository {
  WalkRepositoryImpl({required ApiClient client}) : _client = client;

  final ApiClient _client;

  @override
  Future<WalkProposal?> getCurrentProposal() async {
    final data = await _client.get(ApiEndpoints.currentWalkProposal);
    // 제안이 없으면 204 No Content → ApiClient가 null을 준다.
    if (data == null) return null;
    final json = Json.asMap(data);
    if (json.isEmpty) return null;
    return WalkProposalModel.fromJson(json);
  }

  @override
  Future<void> respondToProposal({
    required int proposalId,
    required bool accepted,
  }) async {
    await _client.post(
      ApiEndpoints.walkProposalResponses(proposalId),
      data: {
        'response': accepted ? 'ACCEPTED' : 'DECLINED',
        'respondedAt': DateTime.now().toUtc().toIso8601String(),
      },
      idempotencyKey: 'proposal-response-$proposalId',
    );
  }

  @override
  Future<Walk> createWalk({
    int? proposalId,
    required int petId,
    required int robotId,
  }) async {
    final data = await _client.post(
      ApiEndpoints.walks,
      data: {
        if (proposalId != null) 'proposalId': proposalId,
        'petId': petId,
        'robotId': robotId,
      },
      // 제안 없는 산책은 멱등키를 붙이지 않는다. 붙일 만한 고유값이 없고, 서버가
      // 진행 중인 앱 산책을 그대로 돌려주므로 두 번 불러도 세션이 하나다.
      idempotencyKey:
          proposalId == null ? null : 'create-walk-$proposalId',
    );
    return WalkModel.fromJson(Json.asMap(data));
  }

  @override
  Future<WalkLocationBatchResult> uploadLocations({
    required int walkId,
    required List<WalkLocationPoint> points,
    String? idempotencyKey,
  }) async {
    final first = points.isEmpty ? 0 : points.first.sequence;
    final data = await _client.post(
      ApiEndpoints.walkLocationsBatch(walkId),
      data: {'points': points.map((p) => p.toJson()).toList()},
      // 같은 구간을 두 번 올려도 중복 저장되지 않도록 시작 sequence를 키에 넣는다.
      idempotencyKey:
          idempotencyKey ?? 'walk-location-batch-$walkId-$first',
    );
    return WalkLocationBatchResultModel.fromJson(Json.asMap(data));
  }

  @override
  Future<Walk> endWalk(int walkId) async {
    final data = await _client.post(
      ApiEndpoints.walkComplete(walkId),
      data: {'endedAt': DateTime.now().toUtc().toIso8601String()},
      // 같은 산책을 두 번 종료해도 한 번만 처리되게 한다(버튼 중복 탭·재시도).
      idempotencyKey: 'walk-end-$walkId',
    );
    return WalkModel.fromJson(Json.asMap(data));
  }

  @override
  Future<Walk> getWalk(int walkId) async {
    final data = await _client.get(ApiEndpoints.walk(walkId));
    return WalkModel.fromJson(Json.asMap(data));
  }

  @override
  Future<CursorPage<Walk>> getWalks({String? cursor, int limit = 20}) async {
    final data = await _client.get(
      ApiEndpoints.walks,
      query: {'limit': limit, if (cursor != null) 'cursor': cursor},
    );

    // 배열로 오는 구현도 있을 수 있어 두 형태를 모두 받아준다.
    if (data is List) {
      return CursorPage<Walk>(
        items: Json.asMapList(data).map(WalkModel.fromJson).toList(growable: false),
      );
    }
    return parseCursorPage<Walk>(Json.asMap(data), WalkModel.fromJson);
  }

  @override
  Future<WalkSummary> getSummary(int walkId) async {
    final data = await _client.get(ApiEndpoints.walkSummary(walkId));
    return WalkSummaryModel.fromJson(Json.asMap(data));
  }

  @override
  Stream<Walk> watchWalk(
    int walkId, {
    Duration interval = const Duration(seconds: 5),
  }) async* {
    while (true) {
      try {
        final walk = await getWalk(walkId);
        yield walk;
        if (walk.status.isFinished) return;
      } on ApiException {
        // 일시적 실패는 다음 주기에 재시도.
      }
      await Future<void>.delayed(interval);
    }
  }
}
