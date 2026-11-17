import '../../bridge/mygo_bridge.dart';
import '../../models/backend/uni_response.dart';
import '../logger_service.dart';
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

/// One term's course offerings, and when the school gave them. The Go side reuses them for
/// thirty minutes unless a refresh asks again.
class CourseOfferings {
  CourseOfferings({required this.fetchedAt, required this.records});

  /// When the school gave these offerings.
  final DateTime fetchedAt;

  final List<CourseScheduleRecord> records;

  factory CourseOfferings.fromJson(Map<String, dynamic> json) {
    return CourseOfferings(
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['fetched_at'] as num).toInt(),
      ),
      records: jsonList(json['records'])
          .map(CourseScheduleRecord.fromJson)
          .toList(),
    );
  }
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

  /// Every offering of the term. The Go side answers from its cache while the cache is
  /// fresh; [forceRefresh] makes it ask the school at once.
  Future<UniResponse<CourseOfferings>> queryAllCoursesForTerm({
    required String termCode,
    bool forceRefresh = false,
  }) {
    return readGo(
      'SmartData.CourseSchedule',
      (json) => CourseOfferings.fromJson(json as Map<String, dynamic>),
      [termCode, forceRefresh],
    );
  }

  /// Keeps the simulated picks of a term on the Go side, with the term's saved timetable, so
  /// the sign-in page's snapshot shows them. [added] are the offering records of the 模拟选课,
  /// [removed] the keys of the 模拟退课. A failed save is logged; the picks stay on this device.
  Future<void> saveDraft({
    required String termCode,
    required List<CourseScheduleRecord> added,
    required List<String> removed,
  }) async {
    try {
      await callGo('SmartData.SaveDraft', [
        termCode,
        [for (final record in added) record.toJson()],
        removed,
      ]);
    } on BridgeException catch (e) {
      LoggerService.error('保存模拟选课失败', error: e.message);
    }
  }
}
