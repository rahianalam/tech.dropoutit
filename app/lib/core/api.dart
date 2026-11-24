import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'config.dart';
import 'i18n.dart';

/// Thin API client. Adds the access token, refreshes it once on 401, and turns
/// server errors into [ApiError] with the server's message.
class Api {
  Api({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage() {
    dio = Dio(BaseOptions(baseUrl: apiUrl, connectTimeout: const Duration(seconds: 15)));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (accessToken != null) options.headers['Authorization'] = 'Bearer $accessToken';
        handler.next(options);
      },
      onError: (e, handler) async {
        final path = e.requestOptions.path;
        if (e.response?.statusCode == 401 && !path.startsWith('/auth/') && await _refresh()) {
          final opts = e.requestOptions..headers['Authorization'] = 'Bearer $accessToken';
          try {
            return handler.resolve(await dio.fetch(opts));
          } on DioException catch (err) {
            return handler.next(err);
          }
        }
        handler.next(e);
      },
    ));
  }

  final FlutterSecureStorage _storage;
  late final Dio dio;
  String? accessToken;
  void Function()? onSessionExpired;

  Future<bool> restore() async {
    final refresh = await _storage.read(key: 'refreshToken');
    if (refresh == null) return false;
    return _refresh();
  }

  Future<void> saveTokens(Map<String, dynamic> body) async {
    accessToken = body['accessToken'] as String;
    await _storage.write(key: 'refreshToken', value: body['refreshToken'] as String);
  }

  Future<void> clear() async {
    final refresh = await _storage.read(key: 'refreshToken');
    if (refresh != null) {
      try {
        await dio.post('/auth/logout', data: {'refreshToken': refresh});
      } catch (_) {}
    }
    accessToken = null;
    await _storage.delete(key: 'refreshToken');
  }

  Future<bool> _refresh() async {
    final refresh = await _storage.read(key: 'refreshToken');
    if (refresh == null) return false;
    try {
      final res = await Dio(BaseOptions(baseUrl: apiUrl)).post('/auth/refresh', data: {'refreshToken': refresh});
      await saveTokens(res.data as Map<String, dynamic>);
      return true;
    } catch (_) {
      accessToken = null;
      await _storage.delete(key: 'refreshToken');
      onSessionExpired?.call();
      return false;
    }
  }

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) =>
      _call(() => dio.get(path, queryParameters: query));
  Future<T> post<T>(String path, [Object? data]) => _call(() => dio.post(path, data: data));
  Future<T> patch<T>(String path, [Object? data]) => _call(() => dio.patch(path, data: data));
  Future<T> put<T>(String path, [Object? data]) => _call(() => dio.put(path, data: data));
  Future<T> delete<T>(String path) => _call(() => dio.delete(path));

  Future<T> _call<T>(Future<Response> Function() fn) async {
    try {
      final res = await fn();
      // NestJS sends an empty body for a null result (e.g. "no application yet").
      final data = res.data;
      return (data is String && data.isEmpty ? null : data) as T;
    } on DioException catch (e) {
      throw ApiError.from(e);
    }
  }
}

class ApiError implements Exception {
  ApiError(this.status, this.message, [this.body]);
  final int? status;
  final String message;
  final Map<String, dynamic>? body;

  factory ApiError.from(DioException e) {
    final data = e.response?.data;
    var message = t('Network problem, please try again', 'নেটওয়ার্ক সমস্যা, আবার চেষ্টা করুন');
    if (data is Map && data['message'] != null) {
      final m = data['message'];
      message = m is List ? m.join('\n') : m.toString();
    }
    return ApiError(e.response?.statusCode, message, data is Map<String, dynamic> ? data : null);
  }

  @override
  String toString() => message;
}
