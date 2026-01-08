
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:async';
import 'dart:convert';
import 'package:eventit/utils/http_client.dart';
import 'package:eventit/screens/checkin_success_screen.dart';
import 'package:eventit/screens/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QrDisplayPage extends StatefulWidget {
  final String ticketCode;
  final String eventTitle;
  final String userName;

  const QrDisplayPage({
    super.key,
    required this.ticketCode,
    required this.eventTitle,
    required this.userName,
  });

  @override
  State<QrDisplayPage> createState() => _QrDisplayPageState();
}

class _QrDisplayPageState extends State<QrDisplayPage> {
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _checkTicketStatus();
    });
  }

  Future<void> _checkTicketStatus() async {
    if (!mounted) {
      _pollingTimer?.cancel();
      return;
    }

    try {
      final response = await HttpClient.get(
        '/api/tickets/status/${widget.ticketCode}',
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['is_checked_in'] == true) {
          _pollingTimer?.cancel();

          Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (context) => CheckinSuccessScreen(
              userName: widget.userName,
              eventTitle: widget.eventTitle,
            ),
          ));
        } else {
          print("Polling: Tiket ${widget.ticketCode} belum check-in.");
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        _pollingTimer?.cancel();
        _handleUnauthorized();
      } else {
        print("Polling error: ${response.statusCode}");
      }
    } catch (e) {
      print("Polling exception: $e");
    }
  }

  void _handleUnauthorized() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await HttpClient.clearCookies();
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesi Anda telah berakhir.'), backgroundColor: Colors.orange),
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
      appBar: AppBar(title: const Text('Tunjukkan Kode Ini')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Tunjukkan kode ini ke panitia', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: widget.ticketCode,
                  version: QrVersions.auto,
                  size: 250.0,
                ),
              ),
              const SizedBox(height: 24),
              Text(widget.userName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(widget.eventTitle, style: const TextStyle(fontSize: 16, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}