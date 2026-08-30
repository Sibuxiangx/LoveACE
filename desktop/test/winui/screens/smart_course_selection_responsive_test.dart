import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loveace/models/aufe/user_credentials.dart';
import 'package:loveace/models/backend/uni_response.dart';
import 'package:loveace/models/jwc/course_schedule_record.dart';
import 'package:loveace/models/jwc/plan_category.dart';
import 'package:loveace/models/jwc/plan_completion_info.dart';
import 'package:loveace/models/jwc/plan_course.dart';
import 'package:loveace/models/jwc/student_schedule.dart';
import 'package:loveace/models/jwc/term_item.dart';
import 'package:loveace/providers/auth_provider.dart';
import 'package:loveace/providers/smart_course_selection_provider.dart';
import 'package:loveace/services/aufe/connector.dart';
import 'package:loveace/services/jwc/class_curriculum_service.dart';
import 'package:loveace/services/jwc/course_schedule_service.dart';
import 'package:loveace/services/jwc/jwc_config.dart';
import 'package:loveace/services/jwc/jwc_service.dart';
import 'package:loveace/services/jwc/plan_service.dart';
import 'package:loveace/services/jwc/student_schedule_service.dart';
import 'package:loveace/winui/screens/winui_smart_course_selection_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _userId = 'responsive-layout-user';
const _termCode = '2026-2027-1-1';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('compact layout remains usable without overflow', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final courses = [
      _course('CS101', '01', '面向对象程序设计与实践（双语实验班）'),
      _course('CS102', '02', '数据库系统原理与大型课程设计'),
      _course('CS103', '03', '计算机网络与分布式系统专题'),
    ];
    final provider = _LayoutProvider(_fakeJwcService(courses));
    await provider.seed();
    for (final course in courses) {
      await provider.addCourse('${course.kch}_${course.kxh}', _userId);
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
            value: _FakeAuthProvider(),
          ),
          ChangeNotifierProvider<SmartCourseSelectionProvider?>.value(
            value: provider,
          ),
        ],
        child: const FluentApp(home: WinUISmartCourseSelectionPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TabView), findsNothing);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(800, 600);
    await tester.pumpAndSettle();
    expect(find.byType(TabView), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(480, 600);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('课程'));
    await tester.pumpAndSettle();
    expect(find.byType(TextBox), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextBox), '分布式 孙老师');
    await tester.pumpAndSettle();
    expect(find.text('全学期课程'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(FluentIcons.filter));
    await tester.pumpAndSettle();
    expect(find.text('隐藏已完成分类'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('计算机网络与分布式系统专题'));
    await tester.pumpAndSettle();
    expect(find.text('课程号'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('培养方案'));
    await tester.pumpAndSettle();
    expect(find.text('3 门本学期可选'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _LayoutProvider extends SmartCourseSelectionProvider {
  _LayoutProvider(super.jwcService);

  bool _seeded = false;

  Future<void> seed() async {
    await super.initialize(_userId);
    _seeded = true;
  }

  @override
  Future<void> initialize(String userId) async {
    if (!_seeded) await super.initialize(userId);
  }
}

class _FakeAuthProvider extends AuthProvider {
  final UserCredentials _credentials = UserCredentials(
    userId: _userId,
    ecPassword: '',
    password: '',
  );

  @override
  UserCredentials get credentials => _credentials;

  @override
  bool get isAuthenticated => true;
}

CourseScheduleRecord _course(String code, String sequence, String name) {
  return CourseScheduleRecord(
    id: '$code-$sequence',
    zxjxjhh: _termCode,
    kch: code,
    kxh: sequence,
    kcm: name,
    xf: 4,
    skjs: '孙老师、王老师',
    bkskrl: 60,
    bkskyl: 18,
    kkxsjc: '计算机与信息工程学院',
    xqm: '龙湖西校区',
    jxlm: '实验中心',
    jasm: '创新实验室 3',
    skxq: 1,
    skjc: 1,
    cxjc: 2,
    skzc: '111111111111111100000000',
    zcsm: '1-16周',
    xkbz: '双语授课，含课程设计与小组展示',
    mxbj: '计算机科学与技术 2025级',
  );
}

_FakeJwcService _fakeJwcService(List<CourseScheduleRecord> courses) {
  return _FakeJwcService(
    courseScheduleService: _FakeCourseScheduleService(courses),
    studentScheduleService: _FakeStudentScheduleService(),
    classCurriculumService: _FakeClassCurriculumService(courses),
    planService: _FakePlanService(courses),
  );
}

AUFEConnection _dummyConnection() {
  return AUFEConnection(userId: _userId, ecPassword: '', password: '');
}

class _FakeJwcService extends JWCService {
  final _FakeCourseScheduleService courseScheduleService;
  final _FakeStudentScheduleService studentScheduleService;
  final _FakeClassCurriculumService classCurriculumService;
  final _FakePlanService planService;

  _FakeJwcService({
    required this.courseScheduleService,
    required this.studentScheduleService,
    required this.classCurriculumService,
    required this.planService,
  }) : super(_dummyConnection());

  @override
  CourseScheduleService get courseSchedule => courseScheduleService;

  @override
  StudentScheduleService get studentSchedule => studentScheduleService;

  @override
  ClassCurriculumService get classCurriculum => classCurriculumService;

  @override
  PlanService get plan => planService;
}

class _FakeCourseScheduleService extends CourseScheduleService {
  final List<CourseScheduleRecord> courses;

  _FakeCourseScheduleService(this.courses)
    : super(_dummyConnection(), JWCConfig());

  @override
  Future<UniResponse<List<ScheduleTermItem>>> getScheduleTerms() async {
    return UniResponse.success([
      ScheduleTermItem(
        termCode: _termCode,
        termName: '2026-2027学年秋季学期',
        isSelected: true,
      ),
    ]);
  }

  @override
  Future<UniResponse<List<CourseScheduleRecord>>> queryAllCoursesForTerm({
    required String termCode,
    void Function(int completed, int total, int records)? onProgress,
  }) async {
    onProgress?.call(1, 1, courses.length);
    return UniResponse.success(courses);
  }
}

class _FakeStudentScheduleService extends StudentScheduleService {
  _FakeStudentScheduleService() : super(_dummyConnection(), JWCConfig());

  @override
  Future<UniResponse<StudentScheduleResponse>> getStudentSchedule(
    String termCode,
  ) async {
    return UniResponse.success(
      StudentScheduleResponse(allUnits: 0, dateList: []),
    );
  }
}

class _FakeClassCurriculumService extends ClassCurriculumService {
  final List<CourseScheduleRecord> courses;

  _FakeClassCurriculumService(this.courses)
    : super(_dummyConnection(), JWCConfig());

  @override
  Future<UniResponse<List<TermItem>>> getTerms() async {
    return UniResponse.success([
      TermItem(
        termCode: _termCode,
        termName: '2026-2027学年秋季学期',
        isCurrent: true,
      ),
    ]);
  }

  @override
  Future<UniResponse<List<CourseScheduleRecord>>> queryClassCurriculum({
    required String planCode,
    required String classCode,
  }) async {
    return UniResponse.success(courses);
  }
}

class _FakePlanService extends PlanService {
  final List<CourseScheduleRecord> courses;

  _FakePlanService(this.courses) : super(_dummyConnection(), JWCConfig());

  @override
  Future<UniResponse<PlanCompletionInfo>> getPlanCompletion({
    String? planId,
    bool forceRefresh = false,
  }) async {
    return UniResponse.success(
      PlanCompletionInfo(
        planName: '计算机科学与技术培养方案',
        major: '计算机科学与技术',
        grade: '2025',
        categories: [
          PlanCategory(
            categoryId: 'core',
            categoryName: '专业核心与实践课程',
            minCredits: 12,
            completedCredits: 0,
            courses: courses
                .map(
                  (course) => PlanCourse(
                    courseCode: course.kch!,
                    courseName: course.kcm!,
                    credits: course.xf!.toDouble(),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
