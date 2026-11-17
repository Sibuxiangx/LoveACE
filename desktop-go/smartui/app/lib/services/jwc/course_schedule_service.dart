import '../../bridge/mygo_bridge.dart';
import '../../models/backend/uni_response.dart';
import '../../models/jwc/course_schedule_record.dart';
import '../../models/jwc/term_item.dart';

class ScheduleTermItem {
  /// 学期代码，如 "2025-2026-1-1"
  final String termCode;

  /// 学期名称，如 "2025-2026学年秋"
  final String termName;

  /// 是否为当前选中的学期
  final bool isSelected;

  ScheduleTermItem({
    required this.termCode,
    required this.termName,
    this.isSelected = false,
  });
}

/// The school's course offerings by term, read through the Go side.
class CourseScheduleService {
  Future<UniResponse<List<ScheduleTermItem>>> getScheduleTerms() {
    return readGo('SmartData.ScheduleTerms', (json) {
      return jsonList(json).map(TermItem.fromJson).map((term) {
        return ScheduleTermItem(
          termCode: term.termCode,
          termName: term.termName,
          isSelected: term.isCurrent,
        );
      }).toList();
    });
  }

  /// Every offering of the term. The Go side reads the term in one call, so
  /// [onProgress] is never called.
  Future<UniResponse<List<CourseScheduleRecord>>> queryAllCoursesForTerm({
    required String termCode,
    void Function(int completed, int total, int records)? onProgress,
  }) {
    return readGo(
      'SmartData.CourseSchedule',
      (json) => jsonList(json).map(CourseScheduleRecord.fromJson).toList(),
      [termCode],
    );
  }
}
