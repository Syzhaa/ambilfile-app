import 'package:flutter/material.dart';

import '../api.dart';
import '../main.dart' show brand;
import '../session.dart';
import '../uploader.dart';

/// Tab Beranda — mirip dashboard /user/ di web:
/// sapaan, kartu statistik, bar penyimpanan, tombol buat room.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<UserRoom> _rooms = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rooms = await Uploader.instance.api.userRooms();
      await SessionManager.instance
          .refreshProfile(Uploader.instance.api.dio);
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
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
    try {
      final room = await Uploader.instance.api.createRoom(minutes);
      await OwnerTokens.save(room.id, room.ownerToken);
      _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Room dibuat! PIN ${room.pin}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: ${AmbilApi.apiError(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SessionManager.instance;
    final active = _rooms.where((r) => !r.isExpired).length;
    final expired = _rooms.length - active;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Beranda',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: brand,
        onPressed: _createRoom,
        icon: const Icon(Icons.add, color: Colors.white),
        label:
            const Text('Buat Room', style: TextStyle(color: Colors.white)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: brand,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListenableBuilder(
              listenable: s,
              builder: (_, __) => Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.orange.shade100,
                    child: Text(
                      s.userName.isNotEmpty
                          ? s.userName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: brand,
                          fontSize: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Halo, ${s.userName}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17)),
                        Text(s.userEmail,
                            style: const TextStyle(
                                color: Colors.black54, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _stat('Room Aktif', '$active', Icons.folder_open),
                const SizedBox(width: 8),
                _stat('Kadaluarsa', '$expired', Icons.history),
                const SizedBox(width: 8),
                _stat('Total', '${_rooms.length}', Icons.dashboard),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: ListenableBuilder(
                  listenable: s,
                  builder: (_, __) {
                    const quota = 2 * 1024 * 1024 * 1024;
                    final pct =
                        (s.storageUsed / quota).clamp(0.0, 1.0);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Penyimpanan',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600)),
                            Text(
                                '${formatBytes(s.storageUsed)} / 2 GB',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                            value: pct,
                            color: brand,
                            backgroundColor: Colors.black12),
                      ],
                    );
                  },
                ),
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                    child: CircularProgressIndicator(color: brand)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: brand, size: 22),
              const SizedBox(height: 6),
              Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18)),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }
}
