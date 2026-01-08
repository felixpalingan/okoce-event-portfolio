
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:eventit/config.dart';
import 'package:http/http.dart' as http;
import 'registration_pages/page_1_nama.dart';
import 'registration_pages/page_2_kontak.dart';
import 'registration_pages/page_3_password.dart';
import 'registration_pages/page_4_profil.dart';
import 'login_screen.dart';
import 'package:eventit/screens/verify_email_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isLoading = false;

  final Map<String, dynamic> _formData = {
    'name': '',
    'phone_number': '',
    'email': '',
    'password': '',
    'province': '',
    'city': '',
    'institution': '',
    'has_business': false,
  };

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      Page1Nama(onNext: (name) {
        setState(() { _formData['name'] = name; });
        _nextPage();
      }),
      Page2Kontak(onNext: (phone, email) {
        setState(() {
          _formData['phone_number'] = phone;
          _formData['email'] = email;
        });
        _nextPage();
      }),
      Page3Password(onNext: (password) {
        setState(() { _formData['password'] = password; });
        _nextPage();
      }),
      Page4Profil(onNext: (province, city, institution, hasBusiness) {
        setState(() {
          _formData['province'] = province;
          _formData['city'] = city;
          _formData['institution'] = institution.isEmpty ? null : institution;
          _formData['has_business'] = hasBusiness;
        });
        _submitRegistration();
      }),
    ];
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeIn,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeIn,
      );
    }
  }

  Future<void> _submitRegistration() async {
    setState(() { _isLoading = true; });
    print("--- DEBUG: Mengirim Data Registrasi ---");
    print(_formData);

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/api/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(_formData),
      );

      if (!mounted) return;
      final data = json.decode(response.body);

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Kode verifikasi dikirim!'),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => VerifyEmailScreen(
              email: data['user_email'],
            ),
          ),
              (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Registrasi Gagal: ${data['message'] ?? 'Terjadi kesalahan'}'),
            backgroundColor: Colors.red,
          ),
        );
        _pageController.animateToPage(
          3,
          duration: const Duration(milliseconds: 300),
          curve: Curves.ease,
        );
      }
    } catch (e) {
      print("Error during registration submission: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Terjadi kesalahan: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _currentPage == 0
            ? null
            : IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isLoading ? null : _previousPage,
        ),
        title: const Text('Buat Akun Baru'),
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(10.0),
            child: Opacity(
              opacity: _isLoading ? 0.5 : 1.0,
              child: LinearProgressIndicator(
                value: (_currentPage + 1) / _pages.length,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.secondary),
              ),
            )
        ),
      ),
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (page) {
              setState(() {
                _currentPage = page;
              });
            },
            children: _pages,
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}