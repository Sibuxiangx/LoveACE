import '../../bridge/mygo_bridge.dart';
import '../../models/backend/uni_response.dart';
import '../../models/jwc/plan_completion_info.dart';

/// The student's training plan and its completion, read through the Go side.
class PlanService {
  /// The Go side reuses the plan for 30 minutes, so the page does not read it again on each
  /// open. forceRefresh is not sent, so it has no effect.
  Future<UniResponse<PlanCompletionInfo>> getPlanCompletion({
    String? planId,
    bool forceRefresh = false,
  }) {
    return readGo(
      'SmartData.PlanCompletion',
      (json) => PlanCompletionInfo.fromJson(json as Map<String, dynamic>),
      [planId],
    );
  }
}
