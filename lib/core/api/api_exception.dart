import 'package:dio/dio.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.address});

  final String message;
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
        return ApiException(msg.replaceFirst('Value error, ', ''), statusCode: status);
      }
    }
    return ApiException('Something went wrong (error $status).', statusCode: status);
  }

  @override
  String toString() => message;
}
