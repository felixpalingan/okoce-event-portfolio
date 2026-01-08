
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:eventit/config.dart';
import 'package:eventit/utils/http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eventit/screens/login_screen.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  int? _userId;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _provinceController = TextEditingController();
  final _cityController = TextEditingController();
  final _institutionController = TextEditingController();
  bool _hasBusiness = false;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      _userId = prefs.getInt('user_id');
      if (_userId == null) throw Exception("Unauthorized");

      final response = await HttpClient.get('/api/users/$_userId');

      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _nameController.text = data['name'] ?? '';
          _phoneController.text = data['phone_number'] ?? '';
          _emailController.text = data['email'] ?? '';
          _provinceController.text = data['province'] ?? '';
          _cityController.text = data['city'] ?? '';
          _institutionController.text = data['institution'] ?? '';
          _hasBusiness = data['has_business'] ?? false;
        });
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Unauthorized');
      } else {
        throw Exception("Gagal memuat profil (${response.statusCode})");
      }
    } catch (e) {
      print("Error fetching profile: $e");
      if (e.toString().contains('Unauthorized')) {
        _handleUnauthorized();
      } else if (mounted) {
        setState(() { _errorMessage = e.toString(); });
      }
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isSaving = true; });

    try {
      if (_userId == null) throw Exception("Unauthorized");

      final response = await HttpClient.post('/api/users/$_userId/update', {
        'name': _nameController.text,
        'phone_number': _phoneController.text,
        'email': _emailController.text,
        'province': _provinceController.text,
        'city': _cityController.text,
        'institution': _institutionController.text,
        'has_business': _hasBusiness,
      });

      if (!mounted) return;

      if (response.statusCode == 200) {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setBool('has_business', _hasBusiness);
        await prefs.setString('user_name', _nameController.text);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil berhasil diperbarui!'), backgroundColor: Colors.green),
        );
        Navigator.of(context).pop();
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        _handleUnauthorized();
      } else {
        final data = json.decode(response.body);
        throw Exception("Gagal menyimpan profil: ${data['message'] ?? response.statusCode}");
      }
    } catch (e) {
      print("Error saving profile: $e");
      if (e.toString().contains('Unauthorized')) {
        _handleUnauthorized();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() { _isSaving = false; });
    }
  }

  void _handleUnauthorized() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await HttpClient.clearCookies();
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesi Anda telah berakhir. Silakan login kembali.'), backgroundColor: Colors.orange),
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
        title: const Text('Edit Profil Akun'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $_errorMessage', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: _fetchProfile,
                child: const Text('Coba Lagi')
            )
          ],
        ),
      ))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: 'Nama Lengkap'), validator: (v) => v!.isEmpty ? 'Wajib diisi' : null, textCapitalization: TextCapitalization.words),
              const SizedBox(height: 16),
              TextFormField(controller: _phoneController, decoration: const InputDecoration(labelText: 'Nomor HP'), keyboardType: TextInputType.phone, validator: (v) => v!.isEmpty ? 'Wajib diisi' : null),
              const SizedBox(height: 16),
              TextFormField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email (Opsional)'), keyboardType: TextInputType.emailAddress, validator: (v) => (v!.isNotEmpty && !v.contains('@')) ? 'Format email tidak valid' : null),
              const SizedBox(height: 16),
              TextFormField(controller: _provinceController, decoration: const InputDecoration(labelText: 'Provinsi'), validator: (v) => v!.isEmpty ? 'Wajib diisi' : null, textCapitalization: TextCapitalization.words),
              const SizedBox(height: 16),
              TextFormField(controller: _cityController, decoration: const InputDecoration(labelText: 'Kabupaten/Kota'), validator: (v) => v!.isEmpty ? 'Wajib diisi' : null, textCapitalization: TextCapitalization.words),
              const SizedBox(height: 16),
              TextFormField(controller: _institutionController, decoration: const InputDecoration(labelText: 'Asal Instansi (Opsional)'), textCapitalization: TextCapitalization.words),

              SwitchListTile(
                title: const Text('Saya punya usaha'),
                subtitle: Text(_hasBusiness ? 'Fitur UMKM akan aktif di Profil' : 'Aktifkan untuk menambah data UMKM'),
                value: _hasBusiness,
                onChanged: (val) => setState(() => _hasBusiness = val),
                contentPadding: EdgeInsets.zero,
                activeColor: Theme.of(context).colorScheme.secondary,
                controlAffinity: ListTileControlAffinity.leading,
              ),

              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSaving ? null : _saveProfile,
                child: _isSaving
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                    : const Text('Simpan Perubahan'),
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _provinceController.dispose();
    _cityController.dispose();
    _institutionController.dispose();
    super.dispose();
  }
}