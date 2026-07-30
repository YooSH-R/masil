import '../entities/walk.dart';
import '../entities/walk_diary.dart';

/// 명세서 2.4 산책 API.
///
/// POST /walks/{walkId}/start 와 /end 는 Jetson 보드가 펫 분리·도킹을 감지해
/// DEVICE_ACCESS_TOKEN으로 호출한다(명세서 6.4, 8.1). 앱에서는 호출하지 않고
/// 상태 조회로 진행 상황을 확인한다.
abstract class WalkRepository {
  /// GET /walk-proposals/current — 현재 산책 제안. 제안이 없으면 204 → null
  Future<WalkProposal?> getCurrentProposal();

  /// POST /walk-proposals/{proposalId}/responses — 제안 수락·거절
  Future<void> respondToProposal({
    required int proposalId,
    required bool accepted,
  });

  /// POST /walks — 산책 세션 생성
  Future<Walk> createWalk({
    required int proposalId,
    required int petId,
    required int robotId,
  });

  /// POST /walks/{walkId}/locations/batch — GPS 좌표 일괄 저장
  Future<WalkLocationBatchResult> uploadLocations({
    required int walkId,
    required List<WalkLocationPoint> points,
    String? idempotencyKey,
  });

  /// GET /walks/{walkId} — 산책 상세 조회
  Future<Walk> getWalk(int walkId);

  /// GET /walks — 산책 목록 조회
  Future<CursorPage<Walk>> getWalks({String? cursor, int limit});

  /// GET /walks/{walkId}/summary — 거리·시간·경로 조회
  Future<WalkSummary> getSummary(int walkId);

  /// 산책 상태를 주기적으로 확인 (Jetson이 시작/종료를 보고할 때까지 대기).
  Stream<Walk> watchWalk(int walkId, {Duration interval});
}
