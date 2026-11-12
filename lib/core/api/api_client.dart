import 'dart:async';

import 'package:dio/dio.dart';

import '../models/token_pair.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';

/// Dio wrapper that attaches the bearer token and refreshes it once on a 401.
class ApiClient {
  ApiClient({required String baseUrl, required this.storage, HttpClientAdapter? adapter})
      : dio = Dio(BaseOptions(baseUrl: baseUrl, connectTimeout: const Duration(seconds: 10))),
        _refreshDio = Dio(BaseOptions(baseUrl: baseUrl, connectTimeout: const Duration(seconds: 10))) {
    if (adapter != null) {
      dio.httpClientAdapter = adapter;
      _refreshDio.httpClientAdapter = adapter;
    }
    dio.interceptors.add(InterceptorsWrapper(onRequest: _onRequest, onError: _onError));
  }

  final Dio dio;
  final TokenStorage storage;
  final Dio _refreshDio;
  Future<bool>? _refreshing;

  static bool _isAuthPath(String path) => path.startsWith('/auth/');

  Future<void> _onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!_isAuthPath(options.path) && options.headers['Authorization'] == null) {
      final tokens = await storage.read();
      if (tokens != null) options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    }
    handler.next(options);
  }

  Future<void> _onError(DioException e, ErrorInterceptorHandler handler) async {
    final options = e.requestOptions;
    final canRefresh = e.response?.statusCode == 401 && !_isAuthPath(options.path) && options.extra['retried'] != true;
    if (!canRefresh) return handler.next(e);

    final ok = await (_refreshing ??= _refresh().whenComplete(() => _refreshing = null));
    if (!ok) return handler.next(e);

    final tokens = await storage.read();
    options.headers['Authorization'] = 'Bearer ${tokens!.accessToken}';
    options.extra['retried'] = true;
    try {
      handler.resolve(await dio.fetch<dynamic>(options));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  Future<bool> _refresh() async {
    final tokens = await storage.read();
    if (tokens == null) return false;
    try {
      final res = await _refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': tokens.refreshToken},
      );
      await storage.save(TokenPair.fromJson(res.data!));
      return true;
    } on DioException {
      await storage.clear();
      return false;
    }
  }

  Future<Map<String, dynamic>> getJson(String path) => _send(() => dio.get<Map<String, dynamic>>(path));

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) =>
      _send(() => dio.post<Map<String, dynamic>>(path, data: body));

  Future<Map<String, dynamic>> _send(Future<Response<Map<String, dynamic>>> Function() call) async {
    try {
      final res = await call();
      return res.data ?? <String, dynamic>{};
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
