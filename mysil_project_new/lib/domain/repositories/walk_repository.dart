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

  /// POST /walks/{walkId}/end — 산책 종료
  ///
  /// **사용자가 `산책 종료` 버튼을 누르는 것이 유일한 종료 트리거다.**
  /// 서버는 이 호출을 받고서야 산책을 끝난 것으로 보고, 감성 사진·일지 생성을
  /// 시작한다. 그래서 남은 좌표를 먼저 다 올린 뒤에 불러야 한다
  /// ([WalkViewModel.endWalk] 가 그 순서를 지킨다).
  Future<Walk> endWalk(int walkId);

  /// GET /walks/{walkId} — 산책 상세 조회
  Future<Walk> getWalk(int walkId);

  /// GET /walks — 산책 목록 조회
  Future<CursorPage<Walk>> getWalks({String? cursor, int limit});

  /// GET /walks/{walkId}/summary — 거리·시간·경로 조회
  Future<WalkSummary> getSummary(int walkId);

  /// 산책 상태를 주기적으로 확인 (Jetson이 시작/종료를 보고할 때까지 대기).
  Stream<Walk> watchWalk(int walkId, {Duration interval});
}
