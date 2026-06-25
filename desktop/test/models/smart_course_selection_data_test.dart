import 'package:flutter_test/flutter_test.dart';
import 'package:loveace/models/jwc/course_schedule_record.dart';
import 'package:loveace/models/jwc/smart_course_selection.dart';

void main() {
  CourseScheduleRecord course(String code, String sequence) {
    return CourseScheduleRecord(
      kch: code,
      kxh: sequence,
      kcm: '$code-$sequence',
      skxq: 1,
      skjc: 1,
      cxjc: 2,
      skzc: '1-16',
    );
  }

  group('SmartCourseSelectionData', () {
    test('persists class curriculum simulation fields', () {
      final data = SmartCourseSelectionData(
        userId: 'user-1',
        termCode: '2025-2026-1-1',
        availableCourses: [course('AVAIL', '01')],
        classCurriculumCourses: [course('CLASS', '01')],
        currentSelectedCourses: const ['ADD_01'],
        removedCourses: const ['CLASS_01'],
        baseScheduleSnapshot: const ['BASE_01'],
        usingClassCurriculum: true,
        classCurriculumName: '软件工程1班',
        classCurriculumCode: 'SE01',
      );

      final restored = SmartCourseSelectionData.fromJson(data.toJson());

      expect(restored.usingClassCurriculum, isTrue);
      expect(restored.classCurriculumName, '软件工程1班');
      expect(restored.classCurriculumCode, 'SE01');
      expect(restored.classCurriculumCourses.single.kch, 'CLASS');
      expect(restored.currentSelectedCourses, const ['ADD_01']);
      expect(restored.removedCourses, const ['CLASS_01']);
      expect(restored.baseScheduleSnapshot, const ['BASE_01']);
    });

    test(
      'keeps simulation results when only available courses are refreshed',
      () {
        final data = SmartCourseSelectionData(
          userId: 'user-1',
          termCode: '2025-2026-1-1',
          availableCourses: [course('OLD', '01')],
          classCurriculumCourses: [course('CLASS', '01')],
          currentSelectedCourses: const ['ADD_01'],
          removedCourses: const ['CLASS_01'],
          usingClassCurriculum: true,
          classCurriculumName: '软件工程1班',
          classCurriculumCode: 'SE01',
        );

        final refreshed = data.copyWith(
          availableCourses: [course('NEW', '01')],
          courseDataRefreshTime: DateTime(2026),
        );

        expect(refreshed.availableCourses.single.kch, 'NEW');
        expect(refreshed.usingClassCurriculum, isTrue);
        expect(refreshed.classCurriculumName, '软件工程1班');
        expect(refreshed.classCurriculumCode, 'SE01');
        expect(refreshed.classCurriculumCourses.single.kch, 'CLASS');
        expect(refreshed.currentSelectedCourses, const ['ADD_01']);
        expect(refreshed.removedCourses, const ['CLASS_01']);
      },
    );

    test(
      'clears class curriculum state when switching back to personal schedule',
      () {
        final data = SmartCourseSelectionData(
          userId: 'user-1',
          termCode: '2025-2026-1-1',
          availableCourses: [course('AVAIL', '01')],
          classCurriculumCourses: [course('CLASS', '01')],
          currentSelectedCourses: const ['ADD_01'],
          removedCourses: const ['CLASS_01'],
          usingClassCurriculum: true,
          classCurriculumName: '软件工程1班',
          classCurriculumCode: 'SE01',
        );

        final personal = data.copyWith(
          classCurriculumCourses: const [],
          usingClassCurriculum: false,
          classCurriculumName: null,
          classCurriculumCode: null,
          currentSelectedCourses: const [],
          removedCourses: const [],
        );

        expect(personal.usingClassCurriculum, isFalse);
        expect(personal.classCurriculumName, isNull);
        expect(personal.classCurriculumCode, isNull);
        expect(personal.classCurriculumCourses, isEmpty);
        expect(personal.currentSelectedCourses, isEmpty);
        expect(personal.removedCourses, isEmpty);
      },
    );
  });
}
