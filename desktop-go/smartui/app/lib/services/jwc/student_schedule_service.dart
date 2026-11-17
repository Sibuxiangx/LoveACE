import '../../bridge/mygo_bridge.dart';
import '../../models/backend/uni_response.dart';
import '../../models/jwc/student_schedule.dart';

/// The student's own timetable for a term, read through the Go side.
class StudentScheduleService {
  Future<UniResponse<StudentScheduleResponse>> getStudentSchedule(
    String termCode,
  ) {
    return readGo(
      'SmartData.StudentSchedule',
      (json) => StudentScheduleResponse.fromJson(json as Map<String, dynamic>),
      [termCode],
    );
  }
}
