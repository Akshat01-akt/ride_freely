import 'dart:async';

import 'package:dio/dio.dart';

import '../models/token_pair.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';

/// Dio wrapper that attaches the bearer token and refreshes it once on a 401.
class ApiClient {
  ApiClient({required String baseUrl, required this.storage, HttpClientAdapter? adapter})
      : dio = Dio(BaseOptions(baseUrl: baseUrl, connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 20))),
        _refreshDio = Dio(BaseOptions(baseUrl: baseUrl, connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 20))) {
    if (adapter != null) {
      dio.httpClientAdapter = adapter;
      _refreshDio.httpClientAdapter = adapter;
    }
    dio.interceptors.add(InterceptorsWrapper(onRequest: _onRequest, onError: _onError));
  }

  final Dio dio;
  final TokenStorage storage;

  String get baseUrl => dio.options.baseUrl;

  /// Points this client (and its token-refresh client) at another backend address.
  set baseUrl(String value) {
    dio.options.baseUrl = value;
    _refreshDio.options.baseUrl = value;
  }
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
    // A multipart body can only be sent once; the retry needs a fresh copy.
    final body = options.data;
    if (body is FormData) options.data = body.clone();
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
    } on DioException catch (e) {
      // Only a definite rejection ends the session; a timeout or 5xx must not log the user out.
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) await storage.clear();
      return false;
    }
  }

  Future<Map<String, dynamic>> getJson(String path, {Map<String, dynamic>? query}) async =>
      _asMap(await _send(() => dio.get<dynamic>(path, queryParameters: query)));

  Future<List<dynamic>> getList(String path) async {
    final data = await _send(() => dio.get<dynamic>(path));
    return data is List ? data : <dynamic>[];
  }

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) async =>
      _asMap(await _send(() => dio.post<dynamic>(path, data: body)));

  Future<Map<String, dynamic>> putJson(String path, Map<String, dynamic> body) async =>
      _asMap(await _send(() => dio.put<dynamic>(path, data: body)));

  Future<Map<String, dynamic>> patchJson(String path, Map<String, dynamic> body) async =>
      _asMap(await _send(() => dio.patch<dynamic>(path, data: body)));

  Future<Map<String, dynamic>> postForm(String path, FormData form) async =>
      _asMap(await _send(() => dio.post<dynamic>(path, data: form)));

  static Map<String, dynamic> _asMap(dynamic data) => data is Map<String, dynamic> ? data : <String, dynamic>{};

  Future<dynamic> _send(Future<Response<dynamic>> Function() call) async {
    try {
      return (await call()).data;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
