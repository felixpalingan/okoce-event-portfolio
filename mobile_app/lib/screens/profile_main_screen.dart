
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eventit/screens/login_screen.dart';
import 'package:eventit/screens/profile_settings_screen.dart';
import 'package:eventit/screens/umkm_list_screen.dart';
import 'package:eventit/utils/http_client.dart';

class ProfileMainScreen extends StatefulWidget {
  const ProfileMainScreen({super.key});

  @override
  State<ProfileMainScreen> createState() => _ProfileMainScreenState();
}

class _ProfileMainScreenState extends State<ProfileMainScreen> {
  String _userName = "Pengguna";
  bool _hasBusiness = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() { _isLoading = true; });
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('user_name') ?? 'Pengguna';
      _hasBusiness = prefs.getBool('has_business') ?? false;
      _isLoading = false;
    });
  }

  Future<void> _logout() async {
    try {
      print("--- Attempting API Logout ---");
      await HttpClient.post('/api/logout', {});
    } catch(e) {
      print("--- Logout API call failed: $e ---");
    } finally {
      _handleUnauthorized();
    }
  }

  void _handleUnauthorized() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await HttpClient.clearCookies();
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anda telah logout.'), backgroundColor: Colors.green),
      );

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
            (Route<dynamic> route) => false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil Saya'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadUserData();
        },
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Container(
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Selamat Datang,',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.blue[700]),
                      ),
                      Text(
                        _userName,
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Colors.blue[900],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Image.asset(
                    'assets/images/logo-okoce.png',
                    height: 50,
                  )
                ],
              ),
            ),
            const SizedBox(height: 24.0),

            const Text(
              'PENGATURAN AKUN',
              style: TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            const Divider(height: 16),

            ListTile(
              leading: const Icon(Icons.person_outline, color: Colors.blue),
              title: const Text('Edit Profil Akun'),
              subtitle: const Text('Perbarui nama, nomor HP, email, dan alamat Anda'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const ProfileSettingsScreen()),
                ).then((_) {
                  _loadUserData();
                });
              },
            ),

            if (_hasBusiness) ...[
              const SizedBox(height: 24.0),
              const Text(
                'PENGATURAN BISNIS',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const Divider(height: 16),

              ListTile(
                leading: Icon(Icons.storefront_outlined, color: Colors.blue[800]),
                title: const Text('Data UMKM Saya'),
                subtitle: const Text('Tambah, edit, atau hapus data UMKM Anda'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const UmkmListScreen()),
                  );
                },
              ),
            ],

            const SizedBox(height: 32.0),
            ListTile(
              leading: const Icon(Icons.logout_outlined, color: Colors.red),
              title: const Text('Logout'),
              subtitle: const Text('Keluar dari akun Anda'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Konfirmasi Logout'),
                    content: const Text('Apakah Anda yakin ingin keluar?'),
                    actions: [
                      TextButton(
                        child: const Text('Batal'),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                      TextButton(
                        child: const Text('Logout', style: TextStyle(color: Colors.red)),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _logout();
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}