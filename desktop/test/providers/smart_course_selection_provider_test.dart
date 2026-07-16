import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:loveace/models/backend/uni_response.dart';
import 'package:loveace/models/jwc/course_schedule_record.dart';
import 'package:loveace/models/jwc/plan_category.dart';
import 'package:loveace/models/jwc/plan_completion_info.dart';
import 'package:loveace/models/jwc/plan_course.dart';
import 'package:loveace/models/jwc/smart_course_selection.dart';
import 'package:loveace/models/jwc/student_schedule.dart';
import 'package:loveace/models/jwc/term_item.dart';
import 'package:loveace/providers/smart_course_selection_provider.dart';
import 'package:loveace/services/aufe/connector.dart';
import 'package:loveace/services/jwc/class_curriculum_service.dart';
import 'package:loveace/services/jwc/course_schedule_service.dart';
import 'package:loveace/services/jwc/jwc_config.dart';
import 'package:loveace/services/jwc/jwc_service.dart';
import 'package:loveace/services/jwc/plan_service.dart';
import 'package:loveace/services/jwc/student_schedule_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const userId = 'user-1';
const termCode = '2025-2026-1-1';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SmartCourseSelectionProvider issue #5 result retention', () {
    test('serializes selection data to a restorable JSON map', () {
      final data = SmartCourseSelectionData(
        userId: userId,
        termCode: termCode,
        availableCourses: [course('ADD', '01')],
        classCurriculumCourses: [course('CLASS', '01')],
        currentSelectedCourses: const ['ADD_01'],
        removedCourses: const ['CLASS_01'],
        usingClassCurriculum: true,
        classCurriculumName: '软件工程1班',
        classCurriculumCode: 'SE01',
      );

      final json = data.toJson();
      final restored = SmartCourseSelectionData.fromJson(json);

      expect(json['available_courses'], isA<List<Map<String, dynamic>>>());
      expect(
        json['class_curriculum_courses'],
        isA<List<Map<String, dynamic>>>(),
      );
      expect(restored.currentSelectedCourses, const ['ADD_01']);
      expect(restored.removedCourses, const ['CLASS_01']);
      expect(restored.usingClassCurriculum, isTrue);
      expect(restored.classCurriculumName, '软件工程1班');
    });

    test(
      'restores simulated selection state after page/provider reload',
      () async {
        final persisted = SmartCourseSelectionData(
          userId: userId,
          termCode: termCode,
          availableCourses: [course('ADD', '01')],
          classCurriculumCourses: [course('CLASS', '01')],
          currentSelectedCourses: const ['ADD_01'],
          removedCourses: const ['CLASS_01'],
          usingClassCurriculum: true,
          classCurriculumName: '软件工程1班',
          classCurriculumCode: 'SE01',
        );
        SharedPreferences.setMockInitialValues({
          'smart_course_selection_$userId': jsonEncode(persisted.toJson()),
        });

        final provider = SmartCourseSelectionProvider(_fakeJwcService());

        await provider.initialize(userId);

        expect(provider.state, SmartCourseSelectionState.loaded);
        expect(provider.usingClassCurriculum, isTrue);
        expect(provider.classCurriculumName, '软件工程1班');
        expect(provider.currentSelectedCourses, const ['ADD_01']);
        expect(provider.removedCourses, const ['CLASS_01']);
        expect(provider.isCourseInSchedule('ADD_01'), isTrue);
        expect(provider.isCourseInSchedule('CLASS_01'), isFalse);
      },
    );

    test('refresh keeps class curriculum simulation results', () async {
      final service = _fakeJwcService();
      final provider = SmartCourseSelectionProvider(service);

      await seedClassCurriculumSimulation(provider);
      service.courseScheduleService.availableCourses = [
        course('ADD', '01'),
        course('NEW', '01'),
      ];

      await provider.refreshCourseData(userId);

      expect(provider.state, SmartCourseSelectionState.loaded);
      expect(provider.usingClassCurriculum, isTrue);
      expect(provider.classCurriculumName, '软件工程1班');
      expect(provider.classCurriculumCourses.map(courseKey), ['CLASS_01']);
      expect(provider.currentSelectedCourses, const ['ADD_01']);
      expect(provider.removedCourses, const ['CLASS_01']);
      expect(provider.availableCourses.map(courseKey), ['ADD_01', 'NEW_01']);
      expect(service.studentScheduleService.getScheduleCalls, 0);
    });

    test(
      'switching back to personal schedule clears class baseline results',
      () async {
        final provider = SmartCourseSelectionProvider(_fakeJwcService());

        await seedClassCurriculumSimulation(provider);
        await provider.switchToPersonalSchedule(userId);

        expect(provider.state, SmartCourseSelectionState.loaded);
        expect(provider.usingClassCurriculum, isFalse);
        expect(provider.classCurriculumName, isNull);
        expect(provider.classCurriculumCourses, isEmpty);
        expect(provider.currentSelectedCourses, isEmpty);
        expect(provider.removedCourses, isEmpty);
        expect(provider.baseScheduleSnapshot, const ['BASE_01']);
        expect(provider.getEffectiveSelectedCourses(), const ['BASE_01']);
      },
    );

    test('reset intentionally clears simulation results', () async {
      final provider = SmartCourseSelectionProvider(_fakeJwcService());

      await seedClassCurriculumSimulation(provider);
      await provider.resetSelection(userId);

      expect(provider.state, SmartCourseSelectionState.loaded);
      expect(provider.usingClassCurriculum, isTrue);
      expect(provider.classCurriculumCourses.map(courseKey), ['CLASS_01']);
      expect(provider.currentSelectedCourses, isEmpty);
      expect(provider.removedCourses, isEmpty);
      expect(provider.getEffectiveSelectedCourses(), const ['CLASS_01']);
    });
  });

  group('SmartCourseSelectionProvider course indexes', () {
    test('groups records by course code and selection key', () async {
      final service = _fakeJwcService(
        availableCourses: [
          course('ADD', '01', startSession: 1),
          course('ADD', '01', startSession: 3),
          course('ADD', '02', startSession: 5),
          course('OTHER', '01', startSession: 7),
        ],
      );
      final provider = SmartCourseSelectionProvider(service);

      await provider.initialize(userId);

      expect(provider.getAvailableCourseRecordsByKey('ADD_01'), hasLength(2));
      expect(provider.getCourseScheduleRecords('ADD'), hasLength(3));
      expect(provider.isCourseAvailableInTerm('ADD'), isTrue);
      expect(provider.isCourseAvailableInTerm('MISSING'), isFalse);
    });

    test('rebuilds indexes after course data refresh', () async {
      final service = _fakeJwcService(availableCourses: [course('OLD', '01')]);
      final provider = SmartCourseSelectionProvider(service);
      await provider.initialize(userId);
      expect(provider.isCourseAvailableInTerm('OLD'), isTrue);

      service.courseScheduleService.availableCourses = [course('NEW', '01')];
      await provider.refreshCourseData(userId);

      expect(provider.isCourseAvailableInTerm('OLD'), isFalse);
      expect(provider.getCourseScheduleRecords('NEW'), hasLength(1));
    });

    test('keeps indexed course data as an immutable snapshot', () async {
      final source = [course('STABLE', '01')];
      final provider = SmartCourseSelectionProvider(
        _fakeJwcService(availableCourses: source),
      );
      await provider.initialize(userId);

      source.add(course('LATE', '01'));

      expect(provider.isCourseAvailableInTerm('STABLE'), isTrue);
      expect(provider.isCourseAvailableInTerm('LATE'), isFalse);
      expect(
        () => provider.availableCourses.add(course('MUTATION', '01')),
        throwsUnsupportedError,
      );
    });

    test('reuses filtered results until data or filters change', () async {
      final provider = SmartCourseSelectionProvider(
        _fakeJwcService(
          availableCourses: [course('ADD', '01'), course('OTHER', '01')],
        ),
      );
      await provider.initialize(userId);

      final first = provider.filteredAvailableCourses;
      final second = provider.filteredAvailableCourses;

      expect(identical(first, second), isTrue);
      provider.setFilter(campus: '东校区');
      expect(identical(first, provider.filteredAvailableCourses), isFalse);
    });

    test('updates a card selection with one notification', () {
      final provider = SmartCourseSelectionProvider(_fakeJwcService());
      final selected = course('SELECTED', '01', startSession: 3);
      var notifications = 0;
      provider.addListener(() => notifications++);

      provider.selectCourseAtTimeSlot(selected, 2, 3);

      expect(provider.selectedCourse, same(selected));
      expect(provider.selectedDay, 2);
      expect(provider.selectedSession, 3);
      expect(notifications, 1);
    });

    test('reuses campus and time slot indexes until filters change', () async {
      final provider = SmartCourseSelectionProvider(
        _fakeJwcService(
          availableCourses: [
            course('ADD', '01', campus: '西校区'),
            course('ADD', '02', campus: '东校区'),
          ],
        ),
      );
      await provider.initialize(userId);

      final campuses = provider.allCampuses;
      final first = provider.getCoursesForTimeSlot(1, 1);

      expect(campuses, const ['东校区', '西校区']);
      expect(identical(campuses, provider.allCampuses), isTrue);
      expect(first, hasLength(2));
      expect(identical(first, provider.getCoursesForTimeSlot(1, 1)), isTrue);

      provider.setFilter(campus: '东校区');
      final filtered = provider.getCoursesForTimeSlot(1, 1);
      expect(identical(first, filtered), isFalse);
      expect(filtered.map((item) => item.kxh), const ['02']);
    });
  });
}

Future<void> seedClassCurriculumSimulation(
  SmartCourseSelectionProvider provider,
) async {
  await provider.useClassCurriculum(
    userId: userId,
    planCode: termCode,
    classCode: 'SE01',
    className: '软件工程1班',
  );
  await provider.addCourse('ADD_01', userId);
  await provider.removeCourse('CLASS_01', userId);

  expect(provider.usingClassCurriculum, isTrue);
  expect(provider.currentSelectedCourses, const ['ADD_01']);
  expect(provider.removedCourses, const ['CLASS_01']);
}

CourseScheduleRecord course(
  String code,
  String sequence, {
  int startSession = 1,
  String? campus,
}) {
  return CourseScheduleRecord(
    kch: code,
    kxh: sequence,
    kcm: '$code-$sequence',
    skxq: 1,
    skjc: startSession,
    cxjc: 2,
    skzc: '1-16',
    xqm: campus,
  );
}

String courseKey(CourseScheduleRecord course) => '${course.kch}_${course.kxh}';

_FakeJwcService _fakeJwcService({
  List<CourseScheduleRecord>? availableCourses,
}) {
  return _FakeJwcService(
    courseScheduleService: _FakeCourseScheduleService(
      availableCourses:
          availableCourses ?? [course('ADD', '01'), course('CLASS', '01')],
    ),
    studentScheduleService: _FakeStudentScheduleService(
      schedule: studentSchedule(['BASE_01']),
    ),
    classCurriculumService: _FakeClassCurriculumService(
      classCourses: [course('CLASS', '01')],
    ),
    planService: _FakePlanService(),
  );
}

StudentScheduleResponse studentSchedule(List<String> keys) {
  return StudentScheduleResponse(
    allUnits: keys.length.toDouble(),
    dateList: [
      ScheduleDateInfo(
        selectCourseList: keys.map((key) {
          final parts = key.split('_');
          return ScheduleCourse(
            id: ScheduleCourseId(
              executiveEducationPlanNumber: termCode,
              coureNumber: parts[0],
              coureSequenceNumber: parts[1],
              studentNumber: userId,
            ),
            courseName: key,
          );
        }).toList(),
      ),
    ],
  );
}

AUFEConnection dummyConnection() {
  return AUFEConnection(userId: userId, ecPassword: 'ec', password: 'pw');
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
  }) : super(dummyConnection());

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
  List<CourseScheduleRecord> availableCourses;

  _FakeCourseScheduleService({required this.availableCourses})
    : super(dummyConnection(), JWCConfig());

  @override
  Future<UniResponse<List<ScheduleTermItem>>> getScheduleTerms() async {
    return UniResponse.success([
      ScheduleTermItem(
        termCode: termCode,
        termName: '2025-2026学年秋',
        isSelected: true,
      ),
    ]);
  }

  @override
  Future<UniResponse<List<CourseScheduleRecord>>> queryAllCoursesForTerm({
    required String termCode,
    void Function(int completed, int total, int records)? onProgress,
  }) async {
    onProgress?.call(1, 1, availableCourses.length);
    return UniResponse.success(availableCourses);
  }
}

class _FakeStudentScheduleService extends StudentScheduleService {
  final StudentScheduleResponse schedule;
  int getScheduleCalls = 0;

  _FakeStudentScheduleService({required this.schedule})
    : super(dummyConnection(), JWCConfig());

  @override
  Future<UniResponse<StudentScheduleResponse>> getStudentSchedule(
    String termCode,
  ) async {
    getScheduleCalls++;
    return UniResponse.success(schedule);
  }
}

class _FakeClassCurriculumService extends ClassCurriculumService {
  final List<CourseScheduleRecord> classCourses;

  _FakeClassCurriculumService({required this.classCourses})
    : super(dummyConnection(), JWCConfig());

  @override
  Future<UniResponse<List<TermItem>>> getTerms() async {
    return UniResponse.success([
      TermItem(termCode: termCode, termName: '2025-2026学年秋', isCurrent: true),
    ]);
  }

  @override
  Future<UniResponse<List<CourseScheduleRecord>>> queryClassCurriculum({
    required String planCode,
    required String classCode,
  }) async {
    return UniResponse.success(classCourses);
  }
}

class _FakePlanService extends PlanService {
  _FakePlanService() : super(dummyConnection(), JWCConfig());

  @override
  Future<UniResponse<PlanCompletionInfo>> getPlanCompletion({
    String? planId,
    bool forceRefresh = false,
  }) async {
    return UniResponse.success(
      PlanCompletionInfo(
        planName: '测试培养方案',
        major: '测试专业',
        grade: '2025',
        categories: [
          PlanCategory(
            categoryId: 'cat',
            categoryName: '测试分类',
            courses: [
              PlanCourse(courseCode: 'ADD', courseName: '新增课程'),
              PlanCourse(courseCode: 'CLASS', courseName: '班级课程'),
              PlanCourse(courseCode: 'BASE', courseName: '个人课程'),
            ],
          ),
        ],
      ),
    );
  }
}
