import 'package:flutter/material.dart';
import 'package:eventit/screens/login_screen.dart';
import 'package:http/http.dart' as http;
import 'package:eventit/config.dart';
import 'dart:convert';
import 'dart:async';

class VerifyEmailScreen extends StatefulWidget {
  final String email;
  const VerifyEmailScreen({super.key, required this.email});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _otpController = TextEditingController();
  bool _isLoading = false;

  late String _currentEmail;
  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;

  @override
  void initState() {
    super.initState();
    _currentEmail = widget.email;
    startCooldown();
  }

  void startCooldown() {
    setState(() {
      _cooldownSeconds = 60;
    });
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_cooldownSeconds > 0) {
        setState(() {
          _cooldownSeconds--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _verifyOtp() async {
    if (_otpController.text.length < 6) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kode OTP harus 6 digit'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() { _isLoading = true; });

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/api/verify-email'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': _currentEmail,
          'otp': _otpController.text,
        }),
      );

      if (!mounted) return;
      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        _cooldownTimer?.cancel();
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Verifikasi Berhasil!'),
            content: const Text('Akun Anda telah aktif. Silakan login untuk melanjutkan.'),
            actions: [
              TextButton(
                child: const Text('OK'),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                        (route) => false,
                  );
                },
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: ${data['message'] ?? 'Error'}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Terjadi kesalahan: ${e.toString()}'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _resendOtp() async {
    setState(() { _isLoading = true; });
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/api/resend-otp'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': _currentEmail}),
      );

      if (!mounted) return;
      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message']), backgroundColor: Colors.green),
        );
        startCooldown();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: ${data['message']}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Terjadi kesalahan: ${e.toString()}'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _showChangeEmailDialog() async {
    final newEmailController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    bool? success = await showDialog<bool>(
      context: context,
      barrierDismissible: !_isLoading,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Ganti Email Verifikasi'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Email saat ini: $_currentEmail'),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: newEmailController,
                      enabled: !_isLoading,
                      decoration: const InputDecoration(labelText: 'Email Baru'),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Email baru wajib diisi';
                        if (!v.contains('@') || !v.contains('.')) return 'Format email tidak valid';
                        if (v == _currentEmail) return 'Email sama dengan saat ini';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.of(ctx).pop(false),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : () async {
                    if (!formKey.currentState!.validate()) return;

                    setDialogState(() { _isLoading = true; });
                    setState(() { _isLoading = true; });

                    try {
                      final response = await http.post(
                        Uri.parse('${AppConfig.apiBaseUrl}/api/change-verification-email'),
                        headers: {'Content-Type': 'application/json'},
                        body: json.encode({
                          'old_email': _currentEmail,
                          'new_email': newEmailController.text,
                        }),
                      );

                      if (!mounted) return;
                      final data = json.decode(response.body);

                      if (response.statusCode == 200) {
                        Navigator.of(ctx).pop(true);
                        setState(() {
                          _currentEmail = data['new_email'];
                          _otpController.clear();
                        });
                        startCooldown();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(data['message']), backgroundColor: Colors.green),
                        );
                      } else {
                        Navigator.of(ctx).pop(false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Gagal: ${data['message']}'), backgroundColor: Colors.red),
                        );
                      }
                    } catch (e) {
                      Navigator.of(ctx).pop(false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
                      );
                    } finally {
                      setDialogState(() { _isLoading = false; });
                      if (mounted) setState(() { _isLoading = false; });
                    }
                  },
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Kirim OTP'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _otpController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isResendButtonDisabled = _cooldownSeconds > 0 || _isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verifikasi Email'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Cek Email Anda',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(
                'Kami telah mengirimkan 6 digit kode OTP ke:\n$_currentEmail',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 16, height: 1.5),
              ),
              TextButton(
                onPressed: _isLoading ? null : _showChangeEmailDialog,
                child: const Text('Salah email? Ganti'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _otpController,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: 'Kode OTP',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  counterText: "",
                ),
                validator: (v) => v == null || v.length != 6 ? 'Kode OTP harus 6 digit' : null,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _verifyOtp,
                child: _isLoading
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                    : const Text('Verifikasi Akun'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: isResendButtonDisabled ? null : _resendOtp,
                child: Text(
                    _cooldownSeconds > 0
                        ? 'Kirim ulang dalam $_cooldownSeconds detik'
                        : 'Tidak menerima kode? Kirim ulang'
                ),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: _isLoading ? null : () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                        (route) => false,
                  );
                },
                child: Text(
                  'Kembali ke Login',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}