import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:csv/csv.dart';
import '../../models/jwc/score_record.dart';
import '../../models/jwc/plan_completion_info.dart';
import '../../models/jwc/plan_category.dart';
import '../../models/aac/aac_credit_info.dart';
import '../../services/logger_service.dart';
import 'csv_exporter_interface.dart';

/// Web平台CSV导出器实现
class CsvExporter implements CsvExporterInterface {
  /// Web平台专用的下载方法
  static Future<void> _downloadCsvFile(
    String csvContent,
    String fileName,
  ) async {
    try {
      // 创建Blob对象
      final parts = [csvContent.toJS].toJS;
      final blob = web.Blob(
        parts,
        web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
      );

      // 创建下载链接
      final url = web.URL.createObjectURL(blob);
      final anchor = web.document.createElement('a') as web.HTMLAnchorElement
        ..href = url
        ..setAttribute('download', fileName)
        ..style.display = 'none';

      // 添加到文档并触发点击
      web.document.body!.appendChild(anchor);
      anchor.click();

      // 清理
      web.document.body!.removeChild(anchor);
      web.URL.revokeObjectURL(url);

      LoggerService.info('💾 CSV文件已下载: $fileName');
    } catch (e) {
      LoggerService.error('❌ Web平台下载CSV文件失败', error: e);
      throw Exception('Web平台下载CSV文件失败: $e');
    }
  }

  @override
  Future<void> exportTermScores(List<ScoreRecord> scores, String termId) async {
    try {
      LoggerService.info('📊 开始导出学期成绩CSV');

      // 创建CSV数据
      List<List<dynamic>> csvData = [
        // 表头
        [
          '序号',
          '学期ID',
          '课程代码',
          '课程班级',
          '课程名称(中文)',
          '课程名称(英文)',
          '学分',
          '学时',
          '课程性质',
          '考试性质',
          '成绩',
          '重修成绩',
          '补考成绩',
        ],
      ];

      // 添加数据行
      for (final score in scores) {
        csvData.add([
          score.sequence,
          score.termId,
          score.courseCode,
          score.courseClass,
          score.courseNameCn,
          score.courseNameEn,
          score.credits,
          score.hours,
          score.courseType ?? '',
          score.examType ?? '',
          score.score,
          score.retakeScore ?? '',
          score.makeupScore ?? '',
        ]);
      }

      // 转换为CSV字符串
      String csvString = const ListToCsvConverter().convert(csvData);

      // 添加BOM以支持Excel正确显示中文
      String csvWithBom = '\uFEFF$csvString';

      final fileName =
          '学期成绩_${termId}_${DateTime.now().millisecondsSinceEpoch}.csv';

      // Web平台下直接触发下载
      await _downloadCsvFile(csvWithBom, fileName);

      LoggerService.info('✅ 学期成绩CSV导出成功');
    } catch (e) {
      LoggerService.error('❌ 导出学期成绩CSV失败', error: e);
      throw Exception('导出CSV失败: $e');
    }
  }

  @override
  Future<void> exportAACScores(List<AACCreditCategory> categories) async {
    try {
      LoggerService.info('📊 开始导出爱安财分数CSV');

      // 创建CSV数据
      List<List<dynamic>> csvData = [
        // 表头
        ['类别ID', '类别名称', '类别总分', '项目ID', '项目标题', '项目类型', '用户编号', '得分', '添加时间'],
      ];

      // 添加数据行
      for (final category in categories) {
        if (category.children.isEmpty) {
          // 如果类别下没有子项目，只显示类别信息
          csvData.add([
            category.id,
            category.typeName,
            category.totalScore,
            '',
            '',
            '',
            '',
            '',
            '',
          ]);
        } else {
          // 为每个子项目添加一行，包含类别信息
          for (final item in category.children) {
            csvData.add([
              category.id,
              category.typeName,
              category.totalScore,
              item.id,
              item.title,
              item.typeName,
              item.userNo,
              item.score,
              item.addTime,
            ]);
          }
        }
      }

      // 转换为CSV字符串
      String csvString = const ListToCsvConverter().convert(csvData);

      // 添加BOM以支持Excel正确显示中文
      String csvWithBom = '\uFEFF$csvString';

      final fileName = '爱安财详细分数_${DateTime.now().millisecondsSinceEpoch}.csv';

      // Web平台下直接触发下载
      await _downloadCsvFile(csvWithBom, fileName);

      LoggerService.info('✅ 爱安财分数CSV导出成功');
    } catch (e) {
      LoggerService.error('❌ 导出爱安财分数CSV失败', error: e);
      throw Exception('导出CSV失败: $e');
    }
  }

  @override
  Future<void> exportPlanCompletionInfo(PlanCompletionInfo planInfo) async {
    try {
      LoggerService.info('📊 开始导出培养方案完成情况CSV');

      // 创建CSV数据
      List<List<dynamic>> csvData = [
        // 表头
        [
          '类别ID',
          '类别名称',
          '最低学分',
          '已修学分',
          '完成率(%)',
          '总课程数',
          '已通过课程数',
          '未通过课程数',
          '缺失必修课数',
          '是否完成',
          '状态描述',
          '课程代码',
          '课程名称',
          '是否通过',
          '学分',
          '成绩',
          '考试日期',
          '课程类型',
          '状态说明',
        ],
      ];

      // 递归添加类别数据
      void addCategoryData(PlanCategory category) {
        if (category.courses.isEmpty) {
          // 如果没有课程，只添加类别信息
          csvData.add([
            category.categoryId,
            category.categoryName,
            category.minCredits,
            category.completedCredits,
            (category.completionPercentage).toStringAsFixed(1),
            category.totalCourses,
            category.passedCourses,
            category.failedCourses,
            category.missingRequiredCourses,
            category.isCompleted ? '是' : '否',
            '', // 状态描述
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
          ]);
        } else {
          // 为每个课程添加一行，包含类别信息
          for (final course in category.courses) {
            csvData.add([
              category.categoryId,
              category.categoryName,
              category.minCredits,
              category.completedCredits,
              (category.completionPercentage).toStringAsFixed(1),
              category.totalCourses,
              category.passedCourses,
              category.failedCourses,
              category.missingRequiredCourses,
              category.isCompleted ? '是' : '否',
              '', // 状态描述
              course.courseCode,
              course.courseName,
              course.isPassed ? '是' : '否',
              course.credits?.toString() ?? '',
              course.score ?? '',
              course.examDate ?? '',
              course.courseType,
              course.statusDescription,
            ]);
          }
        }

        // 递归处理子类别
        for (final subcategory in category.subcategories) {
          addCategoryData(subcategory);
        }
      }

      // 遍历所有类别
      for (final category in planInfo.categories) {
        addCategoryData(category);
      }

      // 转换为CSV字符串
      String csvString = const ListToCsvConverter().convert(csvData);

      // 添加BOM以支持Excel正确显示中文
      String csvWithBom = '\uFEFF$csvString';

      final fileName =
          '培养方案完成情况_${planInfo.major}_${planInfo.grade}_${DateTime.now().millisecondsSinceEpoch}.csv';

      // Web平台下直接触发下载
      await _downloadCsvFile(csvWithBom, fileName);

      LoggerService.info('✅ 培养方案完成情况CSV导出成功');
    } catch (e) {
      LoggerService.error('❌ 导出培养方案完成情况CSV失败', error: e);
      throw Exception('导出CSV失败: $e');
    }
  }
}
