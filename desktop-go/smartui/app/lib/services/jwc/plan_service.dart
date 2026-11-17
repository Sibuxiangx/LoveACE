import '../../bridge/mygo_bridge.dart';
import '../../models/backend/uni_response.dart';
import '../../models/jwc/plan_completion_info.dart';

/// The student's training plan and its completion, read through the Go side.
class PlanService {
  /// The Go side reads the plan on every call, so [forceRefresh] has no effect.
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
