// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'uni_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UniResponse<T> _$UniResponseFromJson<T>(
  Map<String, dynamic> json,
  T Function(Object? json) fromJsonT,
) => UniResponse<T>(
  success: json['success'] as bool,
  data: _$nullableGenericFromJson(json['data'], fromJsonT),
  message: json['message'] as String,
  error: json['error'] as String?,
  retryable: json['retryable'] as bool? ?? false,
);

Map<String, dynamic> _$UniResponseToJson<T>(
  UniResponse<T> instance,
  Object? Function(T value) toJsonT,
) => <String, dynamic>{
  'success': instance.success,
  'data': _$nullableGenericToJson(instance.data, toJsonT),
  'message': instance.message,
  'error': instance.error,
  'retryable': instance.retryable,
};

T? _$nullableGenericFromJson<T>(
  Object? input,
  T Function(Object? json) fromJson,
) => input == null ? null : fromJson(input);

Object? _$nullableGenericToJson<T>(
  T? input,
  Object? Function(T value) toJson,
) => input == null ? null : toJson(input);
