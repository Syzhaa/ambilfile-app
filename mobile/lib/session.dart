import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Menyimpan & mengelola sesi login user (cookie user_session).
/// Login dilakukan via webview Google OAuth (tanpa ubah backend);
/// token cookie diambil dari webview lalu dipakai Dio untuk semua request.
class SessionManager extends ChangeNotifier {
  SessionManager._();
  static final SessionManager instance = SessionManager._();

  static const _kToken = 'user_session_token';

  String? _token;
  Map<String, dynamic>? _user;
  int _storageUsed = 0;
  String _storageLabel = '';
  bool _apiApproved = false;
  bool _apiRequested = false;
  bool _ready = false;

  bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  bool get ready => _ready;
  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  String get userName => (_user?['name'] ?? _user?['email'] ?? '').toString();
  String get userEmail => (_user?['email'] ?? '').toString();
  String get userAvatar => (_user?['avatar_url'] ?? _user?['picture'] ?? '').toString();
  int get storageUsed => _storageUsed;
  String get storageLabel => _storageLabel;
  bool get apiApproved => _apiApproved;
  bool get apiRequested => _apiRequested;

  /// Dipanggil Dio interceptor untuk menyuntik cookie sesi.
  void applyTo(Dio dio) {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (opts, handler) {
        if (isLoggedIn) {
          opts.headers['Cookie'] = 'user_session=$_token';
        }
        handler.next(opts);
      },
    ));
  }

  /// Restore sesi tersimpan saat app dibuka; validasi via /user/me.
  Future<void> restore(Dio dio) async {
    final p = await SharedPreferences.getInstance();
    final t = p.getString(_kToken);
    if (t != null && t.isNotEmpty) {
      _token = t;
      try {
        final r = await dio.get('/user/me',
            options: Options(headers: {'Cookie': 'user_session=$t'}));
        _applyMe(r.data as Map<String, dynamic>);
      } catch (_) {
        await _clearToken();
      }
    }
    _ready = true;
    notifyListeners();
  }

  /// Dipanggil setelah webview login sukses.
  Future<bool> loginWithToken(Dio dio, String token) async {
    _token = token;
    try {
      final r = await dio.get('/user/me',
          options: Options(headers: {'Cookie': 'user_session=$token'}));
      _applyMe(r.data as Map<String, dynamic>);
      final p = await SharedPreferences.getInstance();
      await p.setString(_kToken, token);
      notifyListeners();
      return true;
    } catch (_) {
      _token = null;
      notifyListeners();
      return false;
    }
  }

  void _applyMe(Map<String, dynamic> d) {
    final u = d['user'];
    _user = u is Map ? Map<String, dynamic>.from(u) : null;
    _storageUsed = (d['storage_used_bytes'] as num?)?.toInt() ?? 0;
    _storageLabel = (d['storage_used_label'] ?? '').toString();
    _apiApproved = d['api_approved'] == true;
    _apiRequested = d['api_requested'] == true;
  }

  Future<void> _clearToken() async {
    _token = null;
    _user = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToken);
  }

  /// Refresh profil dari /user/me (dipakai dashboard).
  Future<void> refreshProfile(Dio dio) async {
    if (!isLoggedIn) return;
    try {
      final r = await dio.get('/user/me');
      _applyMe(r.data as Map<String, dynamic>);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> logout(Dio dio) async {
    try {
      await dio.post('/auth/user/logout');
    } catch (_) {}
    await _clearToken();
    notifyListeners();
  }
}
