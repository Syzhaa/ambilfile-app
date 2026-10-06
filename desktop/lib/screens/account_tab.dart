import 'package:flutter/material.dart';

import '../api.dart';
import '../main.dart' show brand, HomeScreen;
import '../session.dart';
import '../uploader.dart';

/// Tab Akun — profil user ala /user/account.html di web.
class AccountTab extends StatefulWidget {
  const AccountTab({super.key});

  @override
  State<AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<AccountTab> {
  Future<void> _logout() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Keluar?'),
        content: const Text('Sesi login di perangkat ini akan dihapus.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Keluar')),
        ],
      ),
    );
    if (yes != true) return;
    await SessionManager.instance.logout(Uploader.instance.api.dio);
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = SessionManager.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Akun',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListenableBuilder(
        listenable: s,
        builder: (_, __) {
          const quota = 2 * 1024 * 1024 * 1024;
          final pct = (s.storageUsed / quota).clamp(0.0, 1.0);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.orange.shade100,
                        backgroundImage: s.userAvatar.isNotEmpty
                            ? NetworkImage(s.userAvatar)
                            : null,
                        child: s.userAvatar.isEmpty
                            ? Text(
                                s.userName.isNotEmpty
                                    ? s.userName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: brand,
                                    fontSize: 24),
                              )
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(s.userName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17)),
                            const SizedBox(height: 2),
                            Text(s.userEmail,
                                style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
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
                      const SizedBox(height: 8),
                      const Text(
                        'Kuota 2 GB untuk semua room milikmu.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.black45),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading:
                      const Icon(Icons.key_outlined, color: brand),
                  title: const Text('Status API'),
                  subtitle: Text(
                    s.apiApproved
                        ? 'Disetujui — bisa bikin API key'
                        : s.apiRequested
                            ? 'Menunggu persetujuan admin'
                            : 'Belum meminta akses',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout, color: Colors.red),
                  label: const Text('Keluar',
                      style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Center(
                child: Text('AmbilFile v1.1.0',
                    style:
                        TextStyle(fontSize: 12, color: Colors.black38)),
              ),
            ],
          );
        },
      ),
    );
  }
}
