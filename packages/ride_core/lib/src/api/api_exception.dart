import 'package:dio/dio.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  factory ApiException.fromDio(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    if (status == null) {
      return const ApiException('Cannot reach the server. Check your connection and try again.');
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
