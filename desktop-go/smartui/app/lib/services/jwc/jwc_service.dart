import 'class_curriculum_service.dart';
import 'course_schedule_service.dart';
import 'plan_service.dart';
import 'student_schedule_service.dart';

/// The school data the smart page reads. The school session lives in the desktop app's Go
/// side; each read is a call to it, and returns the same models as before.
class JWCService {
  final ClassCurriculumService classCurriculum = ClassCurriculumService();
  final CourseScheduleService courseSchedule = CourseScheduleService();
  final PlanService plan = PlanService();
  final StudentScheduleService studentSchedule = StudentScheduleService();
}
