import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../main.dart' show brand, RoomScreen;
import '../uploader.dart';

/// Tab Ruangan — daftar "Ruangan Saya" ala /user/rooms.html di web.
class RoomsTab extends StatefulWidget {
  const RoomsTab({super.key});

  @override
  State<RoomsTab> createState() => _RoomsTabState();
}

class _RoomsTabState extends State<RoomsTab> {
  List<UserRoom> _rooms = [];
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
      final rooms = await Uploader.instance.api.userRooms();
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
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
    final active = _rooms.where((r) => !r.isExpired).toList();
    final expired = _rooms.where((r) => r.isExpired).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ruangan Saya',
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
                : _rooms.isEmpty
                    ? const Center(
                        child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                            'Belum ada ruangan.\nTekan Buat Room untuk mulai.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black45)),
                      ))
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (active.isNotEmpty) ...[
                            const Text('Aktif',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.black54)),
                            const SizedBox(height: 8),
                            for (final r in active) _tile(r),
                            const SizedBox(height: 16),
                          ],
                          if (expired.isNotEmpty) ...[
                            const Text('Kadaluarsa',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.black54)),
                            const SizedBox(height: 8),
                            for (final r in expired) _tile(r),
                          ],
                        ],
                      ),
      ),
    );
  }

  Widget _tile(UserRoom r) {
    return Card(
      child: ListTile(
        leading: Icon(
            r.isExpired ? Icons.history : Icons.folder_open,
            color: r.isExpired ? Colors.grey : brand),
        title: Text('PIN ${r.pin}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            r.isExpired ? 'Kadaluarsa' : 'Aktif',
            style: const TextStyle(fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.copy, size: 20),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: r.pin));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PIN disalin')));
              },
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => RoomScreen(roomId: r.id)),
        ),
      ),
    );
  }
}
