import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'session.dart';
import 'uploader.dart';
import 'screens/shell.dart';
import 'screens/login_screen.dart';
import 'package:dio/dio.dart';

const brand = Color(0xFFF6821F);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Uploader.initForegroundService();
  // Restore sesi login (kalau ada) sebelum UI tampil
  await SessionManager.instance.restore(Uploader.instance.api.dio);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AmbilFile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: brand, primary: brand, surface: Colors.white),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 0),
      ),
      home: ListenableBuilder(
        listenable: SessionManager.instance,
        builder: (_, __) {
          if (!SessionManager.instance.ready) {
            return const Scaffold(
                body: Center(
                    child:
                        CircularProgressIndicator(color: brand)));
          }
          return SessionManager.instance.isLoggedIn
              ? const MainShell()
              : const HomeScreen();
        },
      ),
    );
  }
}

// ============================== HOME ==============================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, String>> recent = [];
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList('recent_rooms') ?? [];
    setState(() {
      recent = raw
          .map((s) => Map<String, String>.from(jsonDecode(s) as Map))
          .toList();
    });
  }

  Future<void> _saveRecent(String id, String pin) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList('recent_rooms') ?? [];
    raw.removeWhere((s) => (jsonDecode(s) as Map)['id'] == id);
    raw.insert(0, jsonEncode({'id': id, 'pin': pin}));
    await p.setStringList('recent_rooms', raw.take(20).toList());
    _loadRecent();
  }

  Future<void> _createRoom() async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Masa berlaku ruangan',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          for (final o in [
            [10, '10 menit'],
            [60, '1 jam'],
            [1440, '1 hari'],
            [10080, '7 hari'],
          ])
            ListTile(
              title: Text(o[1] as String),
              onTap: () => Navigator.pop(c, o[0] as int),
            ),
        ]),
      ),
    );
    if (minutes == null) return;
    setState(() => busy = true);
    try {
      final room = await Uploader.instance.api.createRoom(minutes);
      await OwnerTokens.save(room.id, room.ownerToken);
      await _saveRecent(room.id, room.pin);
      if (!mounted) return;
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => RoomScreen(roomId: room.id)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: ${AmbilApi.apiError(e)}')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _joinPin() async {
    final ctrl = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Gabung pakai PIN'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration:
              const InputDecoration(hintText: 'PIN 6 digit', counterText: ''),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, ctrl.text.trim()),
              child: const Text('Gabung')),
        ],
      ),
    );
    if (pin == null || pin.length != 6) return;
    setState(() => busy = true);
    try {
      final id = await Uploader.instance.api.joinByPin(pin);
      await _saveRecent(id, pin);
      if (!mounted) return;
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => RoomScreen(roomId: id)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: ${AmbilApi.apiError(e)}')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('AmbilFile',
              style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            TextButton(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const LoginScreen())),
              child: const Text('Masuk',
                  style: TextStyle(
                      color: brand, fontWeight: FontWeight.bold)),
            ),
          ]),
      body: busy
          ? const Center(child: CircularProgressIndicator(color: brand))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('Kirim file besar,\nsemudah kirim link.',
                    style:
                        TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Tanpa daftar. Upload tetap jalan walau layar mati.',
                    style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 24),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: brand,
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: _createRoom,
                  icon: const Icon(Icons.add),
                  label: const Text('Buat Ruangan',
                      style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: _joinPin,
                  icon: const Icon(Icons.pin),
                  label: const Text('Gabung pakai PIN',
                      style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 24),
                if (recent.isNotEmpty) ...[
                  const Text('Terakhir dibuka',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),
                  for (final r in recent)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.folder_open, color: brand),
                        title: Text('PIN ${r['pin']}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(r['id'] ?? '',
                            style: const TextStyle(fontSize: 11)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    RoomScreen(roomId: r['id']!))),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

// ============================== ROOM ==============================

class RoomScreen extends StatefulWidget {
  final String roomId;
  const RoomScreen({super.key, required this.roomId});

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}


class _RoomScreenState extends State<RoomScreen> {
  RoomDetail? detail;
  String? error;
  List<Map<String, dynamic>> unfinished = [];
  List<RoomFolder> folders = [];
  List<RoomFile> files = [];
  List<RoomFolder> crumb = []; // breadcrumb folder
  bool picking = false;
  String? ownerToken;

  String? get currentFolderId =>
      crumb.isEmpty ? null : crumb.last.id;
  bool get canDownload =>
      detail == null || detail!.permission != 'view';
  bool get canDelete =>
      detail == null || detail!.allowDelete;

  @override
  void initState() {
    super.initState();
    OwnerTokens.get(widget.roomId).then((t) {
      if (mounted) setState(() => ownerToken = t);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => error = null);
    try {
      final d = await Uploader.instance.api.getRoom(widget.roomId);
      final u =
          await Uploader.instance.unfinishedSessions(widget.roomId);
      final fl = await Uploader.instance.api.listFolders(widget.roomId,
          parentId: currentFolderId);
      final fs = await Uploader.instance.api
          .roomFiles(widget.roomId, folderId: currentFolderId);
      if (!mounted) return;
      setState(() {
        detail = d;
        unfinished = u;
        folders = fl;
        files = fs;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => error = AmbilApi.apiError(e));
    }
  }

  Future<void> _pickAndUpload() async {
    if (picking) return;
    setState(() => picking = true);
    try {
      final res = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (res == null) return;
      for (final f in res.files) {
        final path = f.path;
        if (path == null) continue;
        await Uploader.instance.enqueue(
          roomId: widget.roomId,
          filePath: path,
          folderId: currentFolderId ?? '',
        );
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> _createFolder() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Folder baru'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration:
              const InputDecoration(hintText: 'Nama folder'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(c, ctrl.text.trim()),
              child: const Text('Buat')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await Uploader.instance.api.createFolder(widget.roomId, name,
          parentId: currentFolderId, ownerToken: ownerToken);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: ${AmbilApi.apiError(e)}')));
    }
  }

  Future<void> _deleteFile(RoomFile f) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus file?'),
        content: Text(f.name),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      // Session login atau owner token bisa hapus
      await Uploader.instance.api.dio.delete('/api/file/${f.id}',
          options: Options(headers: {
            if (ownerToken != null && ownerToken!.isNotEmpty)
              'X-Room-Token': ownerToken!,
          }));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: ${AmbilApi.apiError(e)}')));
    }
  }

  Future<void> _deleteFolder(RoomFolder fo) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus folder?'),
        content: Text('${fo.name}\nSemua isi di dalamnya ikut terhapus.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await Uploader.instance.api
          .deleteFolder(fo.id, ownerToken: ownerToken);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: ${AmbilApi.apiError(e)}')));
    }
  }

  Future<void> _download(RoomFile f) async {
    final dir = await getExternalStorageDirectory();
    final savePath = '${dir!.path}/${f.name}';
    if (!mounted) return;

    // State dialog progres (per-byte, mulus)
    int received = 0;
    int total = f.size;
    double mbps = 0;
    bool done = false;
    bool cancelled = false;
    var cancelToken = CancelToken();

    // Penghitung kecepatan (EMA per 500ms)
    int lastBytes = 0;
    var lastAt = DateTime.now();
    double speedBps = 0;
    Timer? ticker;
    StateSetter? setDlg;

    void updateSpeed() {
      final now = DateTime.now();
      final dt = now.difference(lastAt).inMilliseconds / 1000.0;
      if (dt >= 0.4) {
        final inst = (received - lastBytes) / dt;
        speedBps = speedBps == 0 ? inst : speedBps * 0.6 + inst * 0.4;
        lastBytes = received;
        lastAt = now;
        mbps = speedBps * 8 / 1e6;
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) {
          setDlg = setState;
          final pct =
              total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
          return AlertDialog(
            title: Text(f.name,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                    value: pct, color: brand, backgroundColor: Colors.black12),
                const SizedBox(height: 12),
                Text(
                  '${formatBytes(received)} / ${formatBytes(total)} • ${(pct * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  mbps > 0
                      ? '${mbps >= 10 ? mbps.round() : mbps.toStringAsFixed(1)} Mbps'
                      : 'Menghubungkan...',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  cancelled = true;
                  cancelToken.cancel();
                  Navigator.pop(c);
                },
                child: const Text('Batal',
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          );
        },
      ),
    );

    ticker = Timer.periodic(const Duration(milliseconds: 300), (_) {
      updateSpeed();
      setDlg?.call(() {});
    });

    try {
      await Uploader.instance.api.dio.download(
        '/d/${f.id}',
        savePath,
        cancelToken: cancelToken,
        options: Options(receiveTimeout: const Duration(minutes: 30)),
        onReceiveProgress: (a, b) {
          received = a;
          if (b > 0) total = b;
          // update langsung biar mulus, tidak nunggu ticker
          setDlg?.call(() {});
        },
      );
      done = true;
    } catch (e) {
      if (!cancelled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal: ${AmbilApi.apiError(e)}')));
      }
    } finally {
      ticker.cancel();
    }

    if (!mounted) return;
    // tutup dialog kalau masih terbuka
    Navigator.of(context, rootNavigator: true).pop();
    if (done) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Selesai: ${f.name}'),
          action: SnackBarAction(
              label: 'Buka',
              onPressed: () => OpenFilex.open(savePath)),
        ),
      );
    }
  }

  void _share() {
    final link = 'https://ambilfile.web.id/room.html?id=${widget.roomId}';
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Bagikan ruangan',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.link, color: brand),
                title: const Text('Salin link'),
                subtitle: Text(link,
                    style: const TextStyle(fontSize: 11)),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: link));
                  Navigator.pop(c);
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Link disalin')));
                },
              ),
              ListTile(
                leading: const Icon(Icons.pin, color: brand),
                title: const Text('Salin PIN'),
                subtitle: Text('PIN ${detail?.pin ?? ''}'),
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: detail?.pin ?? ''));
                  Navigator.pop(c);
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('PIN disalin')));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFolder(RoomFolder f) {
    setState(() => crumb.add(f));
    _load();
  }

  void _crumbTo(int i) {
    // i = -1 -> root
    setState(() {
      crumb = i < 0 ? [] : crumb.sublist(0, i + 1);
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(detail == null ? 'Ruangan' : 'PIN ${detail!.pin}'),
        actions: [
          IconButton(
              icon: const Icon(Icons.share), onPressed: _share),
          IconButton(
              icon: const Icon(Icons.create_new_folder),
              onPressed: _createFolder),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: brand,
        onPressed: _pickAndUpload,
        icon: const Icon(Icons.upload, color: Colors.white),
        label:
            const Text('Upload', style: TextStyle(color: Colors.white)),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('Coba lagi')),
        ]),
      );
    }
    if (detail == null) {
      return const Center(
          child: CircularProgressIndicator(color: brand));
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: brand,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (unfinished.isNotEmpty)
            Card(
              color: Colors.amber.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(children: [
                        Icon(Icons.history,
                            color: Colors.amber, size: 20),
                        SizedBox(width: 8),
                        Text('Upload belum selesai',
                            style: TextStyle(
                                fontWeight: FontWeight.bold)),
                      ]),
                      const SizedBox(height: 6),
                      for (final s in unfinished)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                              s['fileName']?.toString() ?? '',
                              style:
                                  const TextStyle(fontSize: 13)),
                          subtitle: Text(
                              formatBytes(
                                  (s['fileSize'] as num?)?.toInt() ??
                                      0),
                              style:
                                  const TextStyle(fontSize: 12)),
                          trailing: TextButton(
                            onPressed: () async {
                              final path =
                                  s['filePath']?.toString() ?? '';
                              if (path.isEmpty) return;
                              await Uploader.instance.enqueue(
                                roomId: widget.roomId,
                                filePath: path,
                                reuseFileId:
                                    s['fileId']?.toString(),
                              );
                              _load();
                            },
                            child: const Text('Lanjutkan'),
                          ),
                        ),
                    ]),
              ),
            ),
          _UploadQueue(onDone: _load),
          const SizedBox(height: 8),
          // Breadcrumb folder
          if (crumb.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  TextButton(
                      onPressed: () => _crumbTo(-1),
                      child: const Text('Utama')),
                  for (var i = 0; i < crumb.length; i++) ...[
                    const Text(' / '),
                    TextButton(
                        onPressed: () => _crumbTo(i),
                        child: Text(crumb[i].name)),
                  ],
                ],
              ),
            ),
          Text(
              'Kadaluarsa: ${detail!.expiresAt} • ${detail!.quotaLabel}',
              style: const TextStyle(
                  color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 8),
          if (folders.isEmpty && files.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                  child: Text(
                      'Belum ada file.\nTekan Upload untuk mulai.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black45))),
            ),
          for (final fo in folders)
            Card(
              child: ListTile(
                leading:
                    const Icon(Icons.folder, color: brand),
                title: Text(fo.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                trailing: canDelete
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 20),
                        onPressed: () => _deleteFolder(fo),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: () => _openFolder(fo),
              ),
            ),
          for (final f in files)
            Card(
              child: ListTile(
                leading: const Icon(Icons.insert_drive_file,
                    color: brand),
                title: Text(f.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                subtitle: Text(
                    '${formatBytes(f.size)} • ${f.downloads}x diunduh',
                    style: const TextStyle(fontSize: 12)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (canDownload)
                      IconButton(
                        icon: const Icon(Icons.download),
                        onPressed: () => _download(f),
                      ),
                    if (canDelete)
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 20),
                        onPressed: () => _deleteFile(f),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}


class _UploadQueue extends StatelessWidget {
  final VoidCallback onDone;
  const _UploadQueue({required this.onDone});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Uploader.instance,
      builder: (context, _) {
        final doneJobs = Uploader.instance.jobs
            .where((j) => j.status == JobStatus.done)
            .toList();
        if (doneJobs.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            for (final j in doneJobs) {
              Uploader.instance.removeJob(j);
            }
            onDone();
          });
        }
        final jobs = Uploader.instance.jobs
            .where((j) => j.status != JobStatus.done)
            .toList();
        if (jobs.isEmpty) return const SizedBox.shrink();
        return Card(
          color: Colors.orange.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              for (final j in jobs) ...[
                Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(j.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          Text(
                            '${formatBytes(j.bytesUploaded)} / ${formatBytes(j.fileSize)} • ${(j.progress * 100).toStringAsFixed(0)}%${j.mbps > 0 ? ' • ${j.mbps >= 10 ? j.mbps.round() : j.mbps.toStringAsFixed(1)} Mbps' : ''}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54),
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                              value: j.progress,
                              color: brand,
                              backgroundColor: Colors.black12),
                          if (j.status == JobStatus.failed && j.error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(j.error!,
                                  style: const TextStyle(
                                      color: Colors.red, fontSize: 12)),
                            ),
                        ]),
                  ),
                  if (j.status == JobStatus.failed)
                    IconButton(
                      icon: const Icon(Icons.refresh, color: brand),
                      onPressed: () {
                        Uploader.instance.enqueue(
                            roomId: j.roomId,
                            filePath: j.filePath,
                            reuseFileId: j.fileId);
                      },
                    ),
                ]),
                const SizedBox(height: 8),
              ],
            ]),
          ),
        );
      },
    );
  }
}
