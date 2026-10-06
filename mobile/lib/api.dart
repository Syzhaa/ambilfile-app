import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session.dart';

/// Client untuk AmbilFile backend. Semua endpoint publik (anonim),
/// tanpa perubahan apa pun di sisi web/server.
class AmbilApi {
  final Dio dio;
  final String baseUrl;

  AmbilApi({this.baseUrl = 'https://ambilfile.web.id'})
      : dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(minutes: 10),
          headers: {'Content-Type': 'application/json'},
        )) {
    SessionManager.instance.applyTo(dio);
  }

  Future<Map<String, dynamic>> _get(String path,
      {Map<String, dynamic>? query}) async {
    final r = await dio.get(path, queryParameters: query);
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(String path, Object data) async {
    final r = await dio.post(path, data: data);
    return r.data as Map<String, dynamic>;
  }

  static String apiError(Object e) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map && d['error'] != null) return d['error'].toString();
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return 'Koneksi timeout, coba lagi';
      }
      return 'Koneksi gagal, periksa internet';
    }
    return e.toString();
  }

  /// POST /api/room/create
  Future<RoomInfo> createRoom(int expiryMinutes) async {
    final d = await _post('/api/room/create', {'expiry_minutes': expiryMinutes});
    return RoomInfo(
      id: d['room_id'] as String,
      pin: d['pin']?.toString() ?? '',
      ownerToken: d['owner_token']?.toString(),
    );
  }

  /// GET /api/room/{id}
  Future<RoomDetail> getRoom(String id) async {
    final d = await _get('/api/room/$id');
    final room = d['room'] as Map<String, dynamic>;
    final files = (d['files'] as List? ?? [])
        .map((f) => RoomFile.fromJson(f as Map<String, dynamic>))
        .toList();
    final quota = d['quota_info'] as Map<String, dynamic>?;
    return RoomDetail(
      id: room['id'] as String,
      pin: room['pin']?.toString() ?? '',
      expiresAt: room['expires_at']?.toString() ?? '',
      files: files,
      quotaLabel: quota?['label']?.toString() ?? '',
      permission: d['permission']?.toString() ?? 'both',
      allowDelete: d['allow_delete'] != false,
    );
  }

  /// POST /api/room/pin
  Future<String> joinByPin(String pin) async {
    final d = await _post('/api/room/pin', {'pin': pin});
    return d['room_id'] as String;
  }

  /// GET /api/upload/{roomId}/chunks?fileId= — untuk resume
  Future<Set<int>> chunkStatus(String roomId, String fileId) async {
    final d = await _get('/api/upload/$roomId/chunks',
        query: {'fileId': fileId});
    final list = d['uploaded'] as List? ?? [];
    return list.map((e) => (e as num).toInt()).toSet();
  }

  /// POST /api/upload/{roomId} (satu chunk, multipart)
  /// [onSendProgress] = byte terkirim (0..chunkSize), real-time.
  Future<bool> uploadChunk({
    required String roomId,
    required File chunkFile,
    String folderId = '',
    required int chunkIndex,
    required int totalChunks,
    required String fileId,
    required String originalName,
    required String mimeType,
    required int totalSize,
    required void Function(int sent, int total) onSendProgress,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(chunkFile.path,
          filename: 'chunk_$chunkIndex'),
      'chunkIndex': chunkIndex,
      'totalChunks': totalChunks,
      'fileId': fileId,
      'originalName': originalName,
      'mimeType': mimeType,
      'totalSize': totalSize,
      'folderId': folderId,
    });
    final r = await dio.post(
      '/api/upload/$roomId',
      data: form,
      options: Options(sendTimeout: const Duration(minutes: 15)),
      onSendProgress: onSendProgress,
    );
    final d = r.data;
    return d is Map && d['success'] == true;
  }

  /// GET /d/{id} — download file ke [savePath]
  Future<void> downloadFile(
    String fileId,
    String savePath,
    void Function(int received, int total) onProgress,
  ) async {
    await dio.download('/d/$fileId', savePath,
        onReceiveProgress: onProgress,
        options: Options(receiveTimeout: const Duration(minutes: 30)));
  }

  /// DELETE /api/file/{id} (butuh X-Room-Token owner)
  Future<void> deleteFile(String fileId, String ownerToken) async {
    await dio.delete('/api/file/$fileId',
        options: Options(headers: {'X-Room-Token': ownerToken}));
  }

  /// GET /user/rooms — daftar room milik user yang login
  Future<List<ApiKey>> apiKeys() async {
    final d = await _get('/user/api-keys');
    final l = d['api_keys'] as List? ?? [];
    return l.map((e) => ApiKey.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<String?> createApiKey(String name) async {
    final d = await _post('/user/api-keys', {'name': name});
    // backend: {success, api_key: {id, key, name}, warning}
    final ak = d['api_key'];
    if (ak is Map) return ak['key']?.toString();
    return (d['key'] ?? d['token'])?.toString();
  }

  Future<void> requestApiAccess() async {
    await _post('/user/api-keys/request', {});
  }

  Future<void> deleteApiKey(String id) async {
    await dio.delete('/user/api-keys/$id');
  }

  Future<List<UserRoom>> userRooms() async {
    final d = await _get('/user/rooms');
    final list = d['rooms'] as List? ?? [];
    return list
        .map((r) => UserRoom.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// GET /api/folders/{roomId}?parent_id=
  Future<List<RoomFolder>> listFolders(String roomId,
      {String? parentId}) async {
    final d = await _get('/api/folders/$roomId',
        query: parentId != null ? {'parent_id': parentId} : null);
    final list = d['folders'] as List? ?? [];
    return list
        .map((f) => RoomFolder.fromJson(f as Map<String, dynamic>))
        .toList();
  }

  /// POST /api/folder/create/{roomId}
  Future<void> createFolder(String roomId, String name,
      {String? parentId, String? ownerToken}) async {
    final headers = <String, String>{};
    if (ownerToken != null && ownerToken.isNotEmpty) {
      headers['X-Room-Token'] = ownerToken;
    }
    await dio.post('/api/folder/create/$roomId',
        data: {'name': name, if (parentId != null) 'parent_id': parentId},
        options: Options(headers: headers));
  }

  /// DELETE /api/folder/{id}
  Future<void> deleteFolder(String folderId, {String? ownerToken}) async {
    final headers = <String, String>{};
    if (ownerToken != null && ownerToken.isNotEmpty) {
      headers['X-Room-Token'] = ownerToken;
    }
    await dio.delete('/api/folder/$folderId',
        options: Options(headers: headers));
  }

  /// GET /api/room/{id}?folder_id= — file dalam folder
  Future<List<RoomFile>> roomFiles(String roomId, {String? folderId}) async {
    final d = await _get('/api/room/$roomId',
        query: folderId != null ? {'folder_id': folderId} : null);
    final list = d['files'] as List? ?? [];
    return list
        .map((f) => RoomFile.fromJson(f as Map<String, dynamic>))
        .toList();
  }
}

class RoomInfo {
  final String id;
  final String pin;
  final String? ownerToken;
  RoomInfo({required this.id, required this.pin, this.ownerToken});
}

class RoomDetail {
  final String id;
  final String pin;
  final String expiresAt;
  final List<RoomFile> files;
  final String quotaLabel;
  final String permission;
  final bool allowDelete;
  RoomDetail({
    required this.id,
    required this.pin,
    required this.expiresAt,
    required this.files,
    required this.quotaLabel,
    required this.permission,
    this.allowDelete = true,
  });
}

class RoomFile {
  final String id;
  final String name;
  final int size;
  final int downloads;
  RoomFile(
      {required this.id,
      required this.name,
      required this.size,
      required this.downloads});
  factory RoomFile.fromJson(Map<String, dynamic> j) => RoomFile(
        id: j['id'] as String,
        name: (j['original_name'] ?? j['filename'] ?? '').toString(),
        size: (j['size'] as num?)?.toInt() ?? 0,
        downloads: (j['downloads'] as num?)?.toInt() ?? 0,
      );
}

class RoomFolder {
  final String id;
  final String name;
  final String createdAt;
  RoomFolder({required this.id, required this.name, required this.createdAt});
  factory RoomFolder.fromJson(Map<String, dynamic> j) => RoomFolder(
        id: j['id'].toString(),
        name: (j['name'] ?? '').toString(),
        createdAt: (j['created_at'] ?? '').toString(),
      );
}

class ApiKey {
  final String id;
  final String name;
  final String createdAt;
  final bool isActive;
  ApiKey(
      {required this.id,
      required this.name,
      required this.createdAt,
      required this.isActive});
  factory ApiKey.fromJson(Map<String, dynamic> j) => ApiKey(
        id: j['id'].toString(),
        name: (j['name'] ?? '').toString(),
        createdAt: (j['created_at'] ?? '').toString(),
        isActive: j['is_active'] != false,
      );
}

class UserRoom {
  final String id;
  final String pin;
  final String createdAt;
  final String expiresAt;
  UserRoom(
      {required this.id,
      required this.pin,
      required this.createdAt,
      required this.expiresAt});
  factory UserRoom.fromJson(Map<String, dynamic> j) => UserRoom(
        id: j['id'].toString(),
        pin: (j['pin'] ?? '').toString(),
        createdAt: (j['created_at'] ?? '').toString(),
        expiresAt: (j['expires_at'] ?? '').toString(),
      );

  bool get isExpired {
    try {
      return DateTime.now().isAfter(DateTime.parse(expiresAt).toLocal());
    } catch (_) {
      return false;
    }
  }
}

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const u = ['B', 'KB', 'MB', 'GB'];
  var b = bytes.toDouble();
  var i = 0;
  while (b >= 1024 && i < u.length - 1) {
    b /= 1024;
    i++;
  }
  return '${(b * 100).round() / 100} ${u[i]}';
}

/// Token owner per room (untuk hapus file/folder), disimpan lokal.
class OwnerTokens {
  static Future<void> save(String roomId, String? token) async {
    if (token == null || token.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString('owner_token_$roomId', token);
  }

  static Future<String?> get(String roomId) async {
    final p = await SharedPreferences.getInstance();
    return p.getString('owner_token_$roomId');
  }
}
