import 'package:dio/dio.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.address, this.fieldErrors = const {}});

  final String message;

  /// Problems the server tied to one form answer (key to message), from a 422.
  final Map<String, String> fieldErrors;
  final int? statusCode;

  /// For connection failures: the backend address that was tried, to help diagnose a wrong setting.
  final String? address;

  /// True when no answer came back at all (wrong address, server down, no network).
  bool get isConnectionError => statusCode == null;

  factory ApiException.fromDio(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    if (status == null) {
      return ApiException('Cannot reach the server. Check your connection and try again.', address: e.requestOptions.baseUrl);
    }
    if (data is Map && data['detail'] != null) {
      final detail = data['detail'];
      if (detail is String) return ApiException(detail, statusCode: status);
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        final msg = first is Map ? (first['msg'] ?? '').toString() : first.toString();
        final fields = <String, String>{
          for (final d in detail)
            if (d is Map && d['loc'] is List && (d['loc'] as List).length >= 2 && (d['loc'] as List)[0] == 'answers')
              '${(d['loc'] as List).last}': '${d['msg']}'.replaceFirst('Value error, ', ''),
        };
        return ApiException(msg.replaceFirst('Value error, ', ''), statusCode: status, fieldErrors: fields);
      }
    }
    return ApiException('Something went wrong (error $status).', statusCode: status);
  }

  @override
  String toString() => message;
}
