import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'api.dart';

const int kChunkSize = 5 * 1024 * 1024; // 5MB, sama seperti web
const int kMaxAttempts = 4;
const String kServiceChannelId = 'ambilfile_upload';

/// Callback WAJIB untuk foreground service (jalan di isolate terpisah).
/// Upload-nya sendiri jalan di isolate utama; service ini hanya menjaga
/// proses tetap hidup + menampilkan notifikasi progres.
@pragma('vm:entry-point')
void uploadServiceCallback() {
  FlutterForegroundTask.setTaskHandler(_UploadTaskHandler());
}

class _UploadTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {}
}

enum JobStatus { queued, uploading, paused, failed, done, cancelled }

class UploadJob {
  final String roomId;
  final String folderId;
  final String filePath;
  final String fileName;
  final int fileSize;
  final String fileId;
  JobStatus status = JobStatus.queued;
  int bytesUploaded = 0;
  double mbps = 0;
  String? error;

  UploadJob({
    required this.roomId,
    this.folderId = '',
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    required this.fileId,
  });

  double get progress =>
      fileSize == 0 ? 0 : (bytesUploaded / fileSize).clamp(0.0, 1.0);
}

/// Mesin upload: chunked + resume + retry + foreground service + wakelock.
class Uploader extends ChangeNotifier {
  Uploader._();
  static final Uploader instance = Uploader._();

  final AmbilApi api = AmbilApi();
  final List<UploadJob> jobs = [];
  bool _running = false;

  static void initForegroundService() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: kServiceChannelId,
        channelName: 'Upload AmbilFile',
        channelDescription: 'Menampilkan progres upload file',
        channelImportance: NotificationChannelImportance.DEFAULT,
        priority: NotificationPriority.DEFAULT,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> _ensureService() async {
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      notificationTitle: 'AmbilFile',
      notificationText: 'Menyiapkan upload...',
      serviceTypes: [ForegroundServiceTypes.dataSync],
      callback: uploadServiceCallback,
    );
  }

  Future<void> _updateNotification() async {
    if (!await FlutterForegroundTask.isRunningService) return;
    final active = jobs.where(
        (j) => j.status == JobStatus.uploading || j.status == JobStatus.queued);
    if (active.isEmpty) return;
    final j = active.first;
    final pct = (j.progress * 100).toStringAsFixed(0);
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Mengupload ${j.fileName}',
      notificationText:
          '$pct% • ${formatBytes(j.bytesUploaded)} / ${formatBytes(j.fileSize)}',
    );
  }

  Future<void> _stopServiceIfIdle() async {
    final busy = jobs.any((j) =>
        j.status == JobStatus.uploading || j.status == JobStatus.queued);
    if (!busy && await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
    if (!busy) {
      WakelockPlus.disable();
    }
  }

  /// Identitas stabil file (tahan re-pick): nama + size + head/tail 64KB.
  static Future<String> fileIdentity(String path) async {
    try {
      final f = File(path);
      final size = await f.length();
      final name = path.split('/').last;
      final raf = await f.open();
      final head = await raf.read(65536);
      await raf.setPosition(size > 65536 ? size - 65536 : 0);
      final tail = await raf.read(65536);
      await raf.close();
      var h1 = 0x811c9dc5;
      var h2 = 0x01000193;
      void mix(Uint8List b) {
        for (final byte in b) {
          h1 = ((h1 ^ byte) * 16777619) & 0xffffffff;
          h2 = ((h2 + byte) * 31) & 0xffffffff;
        }
      }

      mix(Uint8List.fromList(utf8.encode('$name|$size')));
      mix(head);
      mix(tail);
      return '${size.toRadixString(36)}_${h1.toRadixString(36)}${h2.toRadixString(36)}';
    } catch (_) {
      return '${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  static Future<String> _sessionKey(String roomId, String identity) async =>
      'af_up_${roomId}_$identity';

  Future<void> _saveSession(UploadJob job, String identity) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _sessionKey(job.roomId, identity);
    await prefs.setString(
        key,
        jsonEncode({
          'fileId': job.fileId,
          'fileName': job.fileName,
          'fileSize': job.fileSize,
          'filePath': job.filePath,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        }));
  }

  Future<void> _clearSession(String roomId, String identity) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(await _sessionKey(roomId, identity));
  }

  /// Sesi upload yang belum selesai di room ini.
  Future<List<Map<String, dynamic>>> unfinishedSessions(String roomId) async {
    final prefs = await SharedPreferences.getInstance();
    final out = <Map<String, dynamic>>[];
    for (final k in prefs.getKeys()) {
      if (!k.startsWith('af_up_${roomId}_')) continue;
      try {
        final m = jsonDecode(prefs.getString(k)!) as Map<String, dynamic>;
        final age = DateTime.now().millisecondsSinceEpoch -
            (m['createdAt'] as int? ?? 0);
        if (age < 7 * 24 * 3600 * 1000) {
          out.add({...m, 'key': k});
        } else {
          await prefs.remove(k);
        }
      } catch (_) {}
    }
    return out;
  }

  /// Tambah file ke antrian upload (atau lanjutkan sesi lama).
  Future<void> enqueue({
    required String roomId,
    required String filePath,
    String? reuseFileId,
    String folderId = '',
  }) async {
    final f = File(filePath);
    if (!await f.exists()) return;
    final size = await f.length();
    final name = filePath.split('/').last;
    final identity = await fileIdentity(filePath);

    // Cari sesi lama untuk file yang sama
    String fileId = reuseFileId ?? '';
    if (fileId.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final key = await _sessionKey(roomId, identity);
      final raw = prefs.getString(key);
      if (raw != null) {
        try {
          fileId = (jsonDecode(raw) as Map)['fileId'] as String? ?? '';
        } catch (_) {}
      }
    }
    fileId = fileId.isEmpty ? const Uuid().v4() : fileId;

    // Jangan duplikat job aktif untuk file yang sama
    if (jobs.any((j) =>
        j.roomId == roomId &&
        j.filePath == filePath &&
        (j.status == JobStatus.uploading || j.status == JobStatus.queued))) {
      return;
    }

    final job = UploadJob(
      roomId: roomId,
      folderId: folderId,
      filePath: filePath,
      fileName: name,
      fileSize: size,
      fileId: fileId,
    );
    jobs.add(job);
    await _saveSession(job, identity);
    notifyListeners();
    _pump();
  }

  void _pump() {
    if (_running) return;
    _running = true;
    _runQueue().whenComplete(() {
      _running = false;
    });
  }

  Future<void> _runQueue() async {
    await _ensureService();
    WakelockPlus.enable();
    try {
      while (true) {
        UploadJob? job;
        for (final j in jobs) {
          if (j.status == JobStatus.queued) {
            job = j;
            break;
          }
        }
        if (job == null) break;
        await _uploadJob(job);
        notifyListeners();
      }
    } finally {
      await _stopServiceIfIdle();
      notifyListeners();
    }
  }

  Future<void> _uploadJob(UploadJob job) async {
    job.status = JobStatus.uploading;
    job.error = null;
    notifyListeners();

    try {
      // Tanya server chunk mana yang sudah sampai (resume)
      Set<int> skip = {};
      try {
        skip = await api.chunkStatus(job.roomId, job.fileId);
      } catch (_) {}

      final totalChunks = (job.fileSize / kChunkSize).ceil();
      final file = File(job.filePath);
      final raf = await file.open();

      int doneBytes = 0;
      int chunkLoaded = 0;
      double speedBps = 0;
      int lastTickBytes = 0;
      var lastTickAt = DateTime.now();
      Timer? ticker;
      ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        final now = DateTime.now();
        final dt =
            now.difference(lastTickAt).inMilliseconds / 1000.0;
        final nowLoaded = doneBytes + chunkLoaded;
        final inst = dt > 0.05
            ? ((nowLoaded - lastTickBytes) / dt).clamp(0.0, double.infinity)
            : 0.0;
        speedBps = speedBps == 0 ? inst : speedBps * 0.6 + inst * 0.4;
        lastTickBytes = nowLoaded;
        lastTickAt = now;
        job.bytesUploaded = nowLoaded;
        job.mbps = speedBps * 8 / 1e6;
        notifyListeners();
        _updateNotification();
      });

      try {
        for (var i = 0; i < totalChunks; i++) {
          final start = i * kChunkSize;
          final end =
              (start + kChunkSize > job.fileSize) ? job.fileSize : start + kChunkSize;
          final size = end - start;

          if (skip.contains(i)) {
            doneBytes += size;
            continue;
          }

          chunkLoaded = 0;
          await raf.setPosition(start);
          final bytes = await raf.read(size);
          await _uploadChunkWithRetry(
            job: job,
            chunkIndex: i,
            totalChunks: totalChunks,
            bytes: bytes,
            onSent: (sent) => chunkLoaded = sent,
          );
          doneBytes += size;
          chunkLoaded = 0;
        }
      } finally {
        ticker.cancel();
        await raf.close();
      }

      job.bytesUploaded = job.fileSize;
      job.mbps = 0;
      job.status = JobStatus.done;
      await _clearSession(job.roomId, await fileIdentity(job.filePath));
    } catch (e) {
      job.status = JobStatus.failed;
      job.error = e is DioException ? AmbilApi.apiError(e) : e.toString();
    }
    notifyListeners();
    _updateNotification();
  }

  /// Upload satu chunk dengan retry 4x, backoff 1s/2s/4s.
  /// Retry: network error, 429, 5xx. Permanen: 4xx lain (413 kuota, dsb).
  Future<void> _uploadChunkWithRetry({
    required UploadJob job,
    required int chunkIndex,
    required int totalChunks,
    required Uint8List bytes,
    required void Function(int sent) onSent,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= kMaxAttempts; attempt++) {
      try {
        final form = FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: 'chunk_$chunkIndex'),
          'chunkIndex': chunkIndex,
          'totalChunks': totalChunks,
          'fileId': job.fileId,
          'originalName': job.fileName,
          'mimeType': _guessMime(job.fileName),
          'totalSize': job.fileSize,
          'folderId': job.folderId,
        });
        final resp = await api.dio.post(
          '/api/upload/${job.roomId}',
          data: form,
          options: Options(sendTimeout: const Duration(minutes: 15)),
          onSendProgress: (sent, total) => onSent(sent),
        );
        final d = resp.data;
        if (d is Map && d['success'] == true) return;
        throw DioException(
            requestOptions: resp.requestOptions,
            response: resp,
            type: DioExceptionType.badResponse);
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        // 4xx selain 429 = permanen
        if (status != null && status != 429 && status < 500) rethrow;
        lastError = e;
      } catch (e) {
        lastError = e;
      }
      if (attempt < kMaxAttempts) {
        await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
      }
    }
    throw lastError ?? Exception('Upload gagal');
  }

  static String _guessMime(String name) {
    final ext = name.split('.').last.toLowerCase();
    const map = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'avi': 'video/x-msvideo',
      'mkv': 'video/x-matroska',
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav',
      'pdf': 'application/pdf',
      'zip': 'application/zip',
      'txt': 'text/plain',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  void cancelJob(UploadJob job) {
    job.status = JobStatus.cancelled;
    notifyListeners();
    _stopServiceIfIdle();
  }

  void removeJob(UploadJob job) {
    jobs.remove(job);
    notifyListeners();
  }
}
