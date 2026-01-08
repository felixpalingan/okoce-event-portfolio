
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:eventit/config.dart';
import 'package:eventit/screens/login_screen.dart';
import 'package:http/http.dart' as http;

class ResetPasswordScreen extends StatefulWidget {
  final String email;
  const ResetPasswordScreen({super.key, required this.email});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;

  bool _isLengthValid = false;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_validatePasswordLengthRealtime);
  }

  void _validatePasswordLengthRealtime() {
    setState(() {
      _isLengthValid = _passwordController.text.length >= 5;
    });
  }

  String? _validatePasswordForm(String? value) {
    if (value == null || value.isEmpty) return 'Password baru tidak boleh kosong';
    if (value.length < 5) return 'Password minimal 5 karakter';
    return null;
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
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
        Uri.parse('${AppConfig.apiBaseUrl}/api/verify-otp-and-reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': widget.email,
          'otp': _otpController.text,
          'new_password': _passwordController.text,
        }),
      );

      if (!mounted) return;
      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Password Berhasil Direset'),
              content: const Text('Silakan login menggunakan password baru Anda.'),
              actions: [
                TextButton(
                    child: const Text('OK'),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (context) => const LoginScreen()),
                            (route) => false,
                      );
                    }
                )
              ],
            )
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: ${data['message'] ?? 'Terjadi Kesalahan'}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      print("Error resetting password: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Terjadi kesalahan jaringan: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  Widget _buildCriteriaRow(String text, bool isValid) {
    final color = isValid ? Colors.green : Colors.red;
    final icon = isValid ? Icons.check_circle_outline : Icons.highlight_off;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: color, fontSize: 13)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _otpController.dispose();
    _passwordController.removeListener(_validatePasswordLengthRealtime);
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Masukkan Kode Verifikasi',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),

                Text(
                  'Kami telah mengirimkan 6 digit kode OTP ke email:\n${widget.email}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 16, height: 1.5),
                ),

                const SizedBox(height: 24),
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
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password Baru'),
                  validator: _validatePasswordForm,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                ),
                const SizedBox(height: 8),
                _buildCriteriaRow('Minimal 5 karakter', _isLengthValid),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Konfirmasi Password Baru'),
                  validator: (v) => v != _passwordController.text ? 'Password tidak cocok' : null,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isLoading ? null : _resetPassword,
                  child: _isLoading
                      ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                      : const Text('Reset Password'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}