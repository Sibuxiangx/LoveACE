// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'course_schedule_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CourseScheduleRecord _$CourseScheduleRecordFromJson(
  Map<String, dynamic> json,
) => CourseScheduleRecord(
  id: json['id'] as String?,
  zxjxjhh: json['zxjxjhh'] as String?,
  kch: json['kch'] as String?,
  kxh: json['kxh'] as String?,
  kcm: json['kcm'] as String?,
  xf: (json['xf'] as num?)?.toInt(),
  xs: (json['xs'] as num?)?.toInt(),
  kkxsh: json['kkxsh'] as String?,
  kkxsjc: json['kkxsjc'] as String?,
  kslxdm: json['kslxdm'] as String?,
  kslxmc: json['kslxmc'] as String?,
  skjs: json['skjs'] as String?,
  bkskrl: (json['bkskrl'] as num?)?.toInt(),
  bkskyl: (json['bkskyl'] as num?)?.toInt(),
  xkmsdm: json['xkmsdm'] as String?,
  xkmssm: json['xkmssm'] as String?,
  xkkzdm: json['xkkzdm'] as String?,
  xkkzsm: json['xkkzsm'] as String?,
  xkkzh: json['xkkzh'] as String?,
  xkxzsm: json['xkxzsm'] as String?,
  kkxqh: json['kkxqh'] as String?,
  kkxqm: json['kkxqm'] as String?,
  xqh: json['xqh'] as String?,
  jxlh: json['jxlh'] as String?,
  jash: json['jash'] as String?,
  skzc: json['skzc'] as String?,
  skxq: (json['skxq'] as num?)?.toInt(),
  skjc: (json['skjc'] as num?)?.toInt(),
  cxjc: (json['cxjc'] as num?)?.toInt(),
  zcsm: json['zcsm'] as String?,
  kclbdm: json['kclbdm'] as String?,
  kclbmc: json['kclbmc'] as String?,
  xkbz: json['xkbz'] as String?,
  xqm: json['xqm'] as String?,
  jxlm: json['jxlm'] as String?,
  jasm: json['jasm'] as String?,
  mxbj: json['mxbj'] as String?,
  xss: (json['xss'] as num?)?.toInt(),
);

Map<String, dynamic> _$CourseScheduleRecordToJson(
  CourseScheduleRecord instance,
) => <String, dynamic>{
  'id': instance.id,
  'zxjxjhh': instance.zxjxjhh,
  'kch': instance.kch,
  'kxh': instance.kxh,
  'kcm': instance.kcm,
  'xf': instance.xf,
  'xs': instance.xs,
  'kkxsh': instance.kkxsh,
  'kkxsjc': instance.kkxsjc,
  'kslxdm': instance.kslxdm,
  'kslxmc': instance.kslxmc,
  'skjs': instance.skjs,
  'bkskrl': instance.bkskrl,
  'bkskyl': instance.bkskyl,
  'xkmsdm': instance.xkmsdm,
  'xkmssm': instance.xkmssm,
  'xkkzdm': instance.xkkzdm,
  'xkkzsm': instance.xkkzsm,
  'xkkzh': instance.xkkzh,
  'xkxzsm': instance.xkxzsm,
  'kkxqh': instance.kkxqh,
  'kkxqm': instance.kkxqm,
  'xqh': instance.xqh,
  'jxlh': instance.jxlh,
  'jash': instance.jash,
  'skzc': instance.skzc,
  'skxq': instance.skxq,
  'skjc': instance.skjc,
  'cxjc': instance.cxjc,
  'zcsm': instance.zcsm,
  'kclbdm': instance.kclbdm,
  'kclbmc': instance.kclbmc,
  'xkbz': instance.xkbz,
  'xqm': instance.xqm,
  'jxlm': instance.jxlm,
  'jasm': instance.jasm,
  'mxbj': instance.mxbj,
  'xss': instance.xss,
};

CourseSchedulePageContext _$CourseSchedulePageContextFromJson(
  Map<String, dynamic> json,
) => CourseSchedulePageContext(totalCount: (json['totalCount'] as num).toInt());

Map<String, dynamic> _$CourseSchedulePageContextToJson(
  CourseSchedulePageContext instance,
) => <String, dynamic>{'totalCount': instance.totalCount};

CourseScheduleList _$CourseScheduleListFromJson(Map<String, dynamic> json) =>
    CourseScheduleList(
      pageSize: (json['pageSize'] as num).toInt(),
      pageNum: (json['pageNum'] as num).toInt(),
      pageContext: CourseSchedulePageContext.fromJson(
        json['pageContext'] as Map<String, dynamic>,
      ),
      records: (json['records'] as List<dynamic>)
          .map((e) => CourseScheduleRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$CourseScheduleListToJson(CourseScheduleList instance) =>
    <String, dynamic>{
      'pageSize': instance.pageSize,
      'pageNum': instance.pageNum,
      'pageContext': instance.pageContext,
      'records': instance.records,
    };

CourseScheduleResponse _$CourseScheduleResponseFromJson(
  Map<String, dynamic> json,
) => CourseScheduleResponse(
  pfcx: (json['pfcx'] as num).toInt(),
  list: CourseScheduleList.fromJson(json['list'] as Map<String, dynamic>),
);

Map<String, dynamic> _$CourseScheduleResponseToJson(
  CourseScheduleResponse instance,
) => <String, dynamic>{'pfcx': instance.pfcx, 'list': instance.list};
