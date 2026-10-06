import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../main.dart' show brand;
import '../session.dart';
import '../uploader.dart';

/// Tab API Key — ala /user/api-keys.html di web.
/// Minta persetujuan admin dulu, baru bisa bikin key.
class ApiKeyTab extends StatefulWidget {
  const ApiKeyTab({super.key});

  @override
  State<ApiKeyTab> createState() => _ApiKeyTabState();
}

class _ApiKeyTabState extends State<ApiKeyTab> {
  List<ApiKey> _keys = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SessionManager.instance
          .refreshProfile(Uploader.instance.api.dio);
      final keys = await Uploader.instance.api.apiKeys();
      if (!mounted) return;
      setState(() {
        _keys = keys;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AmbilApi.apiError(e);
        _loading = false;
      });
    }
  }

  Future<void> _requestAccess() async {
    try {
      await Uploader.instance.api.requestApiAccess();
      _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Permintaan dikirim. Tunggu persetujuan admin.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: ${AmbilApi.apiError(e)}')));
    }
  }

  Future<void> _createKey() async {
    final nameCtrl = TextEditingController(text: 'AmbilFile App');
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Buat API Key'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
              labelText: 'Nama key', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, nameCtrl.text.trim()),
              child: const Text('Buat')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final raw = await Uploader.instance.api.createApiKey(name);
      _load();
      if (!mounted) return;
      // Tampilkan key mentah sekali saja
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: const Text('API Key dibuat'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Salin sekarang — key ini tidak akan ditampilkan lagi:',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(8)),
                child: SelectableText(raw ?? '-',
                    style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 12)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (raw != null) {
                  Clipboard.setData(ClipboardData(text: raw));
                }
                Navigator.pop(c);
              },
              child: const Text('Salin & Tutup'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: ${AmbilApi.apiError(e)}')));
    }
  }

  Future<void> _deleteKey(ApiKey k) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus API Key?'),
        content: Text('Key "${k.name}" akan dihapus permanen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await Uploader.instance.api.deleteApiKey(k.id);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: ${AmbilApi.apiError(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API Key',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: brand,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: brand))
            : _error != null
                ? Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                        Text(_error!,
                            style:
                                const TextStyle(color: Colors.red)),
                        TextButton(
                            onPressed: _load,
                            child: const Text('Coba lagi')),
                      ]))
                : ListenableBuilder(
                    listenable: SessionManager.instance,
                    builder: (_, __) {
                      final s = SessionManager.instance;
                      if (!s.apiApproved) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.key_off,
                                    size: 56, color: Colors.black26),
                                const SizedBox(height: 16),
                                const Text(
                                  'Akses API butuh persetujuan admin.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  s.apiRequested
                                      ? 'Permintaanmu sedang menunggu persetujuan.'
                                      : 'Kamu belum meminta akses API.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 13),
                                ),
                                const SizedBox(height: 16),
                                if (!s.apiRequested)
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                        backgroundColor: brand),
                                    onPressed: _requestAccess,
                                    icon: const Icon(Icons.send),
                                    label: const Text('Minta Akses API'),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }
                      return ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Key saya',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                    backgroundColor: brand),
                                onPressed: _createKey,
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Buat Key'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_keys.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(
                                  child: Text(
                                      'Belum ada API key.',
                                      style: TextStyle(
                                          color: Colors.black45))),
                            )
                          else
                            for (final k in _keys)
                              Card(
                                child: ListTile(
                                  leading: Icon(Icons.key,
                                      color: k.isActive
                                          ? brand
                                          : Colors.grey),
                                  title: Text(k.name,
                                      style: const TextStyle(
                                          fontWeight:
                                              FontWeight.w600)),
                                  subtitle: Text(
                                      k.isActive
                                          ? 'Aktif'
                                          : 'Nonaktif',
                                      style: const TextStyle(
                                          fontSize: 12)),
                                  trailing: IconButton(
                                    icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red),
                                    onPressed: () =>
                                        _deleteKey(k),
                                  ),
                                ),
                              ),
                        ],
                      );
                    },
                  ),
      ),
    );
  }
}
