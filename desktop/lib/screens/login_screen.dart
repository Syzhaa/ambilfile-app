import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:url_launcher/url_launcher.dart';
import '../session.dart';
import '../uploader.dart';
import 'shell.dart';

/// Login Google via browser HP asli (bukan webview di dalam aplikasi).
/// Alur: browser -> Google -> server -> deep link ambilfile://login?token=...
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Login desktop: buka browser, user copy token dari halaman web,
  /// paste di dialog.
  Future<void> _loginDesktop() async {
    final base = Uploader.instance.api.baseUrl;
    final url = Uri.parse('$base/auth/user/google?app=desktop');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      setState(() => _error = 'Gagal membuka browser.');
      return;
    }
    if (!mounted) return;
    final ctrl = TextEditingController();
    final token = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Paste Token Login'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Setelah login di browser, copy token dari halaman web lalu paste di sini:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Token',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(c, ctrl.text.trim()),
              child: const Text('Masuk')),
        ],
      ),
    );
    if (token == null || token.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await SessionManager.instance.loginWithToken(
          Uploader.instance.api.dio, token);
      if (!ok) throw StateError('Token tidak valid. Coba lagi ya.');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainShell()),
      );
    } catch (e) {
      setState(() => _error =
          e is StateError ? e.message : 'Login gagal. Coba lagi ya.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _login() async {
    if (_isDesktop) {
      await _loginDesktop();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Buka di browser HP (Chrome Custom Tab): sesi Google asli kebawa,
      // tidak kena blokir "disallowed_useragent" seperti webview.
      final base = Uploader.instance.api.baseUrl;
      final result = await FlutterWebAuth2.authenticate(
        url: '$base/auth/user/google?app=1',
        callbackUrlScheme: 'ambilfile',
      );
      final uri = Uri.parse(result);
      final token = uri.queryParameters['token'];
      if (token == null || token.isEmpty) {
        throw StateError('Token login tidak ditemukan.');
      }
      final session = SessionManager.instance;
      final ok = await session.loginWithToken(
          Uploader.instance.api.dio, token);
      if (!ok) throw StateError('Sesi tidak valid. Coba lagi ya.');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainShell()),
      );
      final nama = session.userName;
      if (nama.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Halo, $nama!')),
        );
      }
    } on StateError catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      // User batal di browser -> anggap batal, bukan error.
      final msg = e.toString();
      if (msg.contains('CANCELED') || msg.contains('canceled')) {
        setState(() => _error = null);
      } else {
        setState(() => _error = 'Login gagal. Coba lagi ya.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1F2937)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              const Icon(Icons.cloud_upload_outlined,
                  size: 72, color: Color(0xFFF6821F)),
              const SizedBox(height: 24),
              const Text(
                'Masuk ke AmbilFile',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1F2937)),
              ),
              const SizedBox(height: 12),
              const Text(
                'Login untuk menghubungkan room ke akunmu dan memakai kuota 2 GB.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 36),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _login,
                  icon: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.login, color: Colors.white),
                  label: Text(
                    _busy ? 'Membuka browser...' : 'Masuk dengan Google',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF6821F),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Color(0xFFDC2626), fontSize: 13)),
                ),
              ],
              const Spacer(),
              const Text(
                'Login dibuka di browser HP biar aman.\nTanpa login kamu tetap bisa bikin room (kuota 1 GB).',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
