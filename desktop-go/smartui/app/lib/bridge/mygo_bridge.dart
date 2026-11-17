import 'dart:convert';
import 'dart:js_interop';

import '../models/backend/uni_response.dart';
import '../services/logger_service.dart';

/// Defined in web/index.html. It calls a method of a Go service bound with mygo and
/// resolves to the JSON text of the result. The arguments are a JSON array.
@JS('smartCall')
external JSPromise<JSString> _smartCall(JSString method, JSString args);

/// A call the Go side failed, or could not be made.
class BridgeException implements Exception {
  BridgeException(this.method, this.message);

  final String method;
  final String message;

  @override
  String toString() => '$method: $message';
}

/// Calls a method of the Go side and decodes its JSON result.
Future<Object?> callGo(String method, [List<Object?> args = const []]) async {
  final String text;
  try {
    text = (await _smartCall(method.toJS, jsonEncode(args).toJS).toDart).toDart;
  } catch (e) {
    throw BridgeException(method, e.toString());
  }
  return jsonDecode(text);
}

/// Reads a value from the Go side as a [UniResponse], as the school services do: a failed
/// call is a failed response, not an exception.
Future<UniResponse<T>> readGo<T>(
  String method,
  T Function(Object? json) parse, [
  List<Object?> args = const [],
]) async {
  try {
    final json = await callGo(method, args);
    return UniResponse.success(parse(json));
  } on BridgeException catch (e) {
    LoggerService.error('智能排课读取失败', error: e.message);
    return UniResponse(success: false, message: e.message, error: e.message);
  }
}

/// The JSON array of objects the Go side sends; null is an empty list.
List<Map<String, dynamic>> jsonList(Object? json) {
  return (json as List<dynamic>? ?? const <dynamic>[]).cast<Map<String, dynamic>>();
}
