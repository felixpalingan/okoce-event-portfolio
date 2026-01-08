
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:eventit/config.dart'; 
import 'package:eventit/utils/http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eventit/screens/login_screen.dart'; 

class EventDetailPage extends StatefulWidget {
  final Map<String, dynamic> event;
  const EventDetailPage({super.key, required this.event});

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  bool _isProcessing = false;
  Future<Map<String, dynamic>>? _registrationStatusFuture;

  @override
  void initState() {
    super.initState();
    _registrationStatusFuture = _checkRegistrationStatus();
  }

  Future<Map<String, dynamic>> _checkRegistrationStatus() async {
    try {
      if (widget.event['tgl_buka_pendaftaran'] == null ||
          widget.event['tgl_tutup_pendaftaran'] == null) {
        return {'isEnabled': false, 'text': 'Info Pendaftaran Tidak Tersedia'};
      }
      final buka = DateTime.parse(widget.event['tgl_buka_pendaftaran']);
      final tutup = DateTime.parse(widget.event['tgl_tutup_pendaftaran']);
      final now = DateTime.now();

      if (now.isBefore(buka)) {
        return {'isEnabled': false, 'text': 'Pendaftaran Belum Dibuka'};
      }
      if (now.isAfter(tutup)) {
        return {'isEnabled': false, 'text': 'Pendaftaran Ditutup'};
      }

      SharedPreferences prefs = await SharedPreferences.getInstance();
      int? userId = prefs.getInt('user_id');
      bool isUmkmRequired = widget.event['is_umkm_data_required'] ?? false;

      if (userId == null) {
        return {'isEnabled': false, 'text': 'Silakan Login Dahulu'};
      }

      if (isUmkmRequired) {
        print("--- DEBUG: Event wajib UMKM, cek data bisnis... ---");
        final businessResponse = await HttpClient.get('/api/user/businesses');

        if (businessResponse.statusCode == 200) {
          final List<dynamic> myBusinesses = json.decode(businessResponse.body);
          if (myBusinesses.isEmpty) {
            print("--- DEBUG: User belum punya data UMKM. Tombol nonaktif. ---");
            return {'isEnabled': false, 'text': 'Wajib Isi Data UMKM Dahulu'};
          }
          print("--- DEBUG: User punya ${myBusinesses.length} data UMKM. Lanjut cek tiket. ---");
        } else if (businessResponse.statusCode == 401) {
          _handleUnauthorized();
          return {'isEnabled': false, 'text': 'Sesi Habis'};
        } else {
          return {'isEnabled': false, 'text': 'Gagal Cek Data UMKM'};
        }
      }

      final response = await HttpClient.get('/api/users/$userId/tickets');
      if (response.statusCode == 200) {
        final List<dynamic> myTickets = json.decode(response.body);
        bool alreadyRegistered = myTickets.any((ticket) => ticket['event_id'] == widget.event['id']);

        if (alreadyRegistered) {
          return {'isEnabled': false, 'text': 'Anda Sudah Terdaftar'};
        } else {
          if (widget.event['price'] == 0) {
            return {'isEnabled': true, 'text': 'Dapatkan Tiket Gratis'};
          } else {
            return {'isEnabled': false, 'text': 'Pembayaran Belum Tersedia'};
          }
        }
      } else if (response.statusCode == 401) {
        _handleUnauthorized();
        return {'isEnabled': false, 'text': 'Sesi Habis'};
      } else {
        print("Error fetching user tickets: ${response.statusCode}");
        return {'isEnabled': false, 'text': 'Gagal Memeriksa Tiket'};
      }
    } catch (e) {
      print("Error checking registration status: $e");
      if (e.toString().contains('Unauthorized')) {
        _handleUnauthorized();
        return {'isEnabled': false, 'text': 'Sesi Habis'};
      }
      return {'isEnabled': false, 'text': 'Terjadi Kesalahan'};
    }
  }

  Future<void> _getFreeTicket() async {
    setState(() { _isProcessing = true; });
    try {
      final response = await HttpClient.post('/api/tickets/buy', {
        'event_id': widget.event['id']
      });
      if (!mounted) return;
      final data = json.decode(response.body);
      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tiket berhasil didapatkan!'), backgroundColor: Colors.green),
        );
        Navigator.of(context).pop(true);
      } else if (response.statusCode == 401) {
        _handleUnauthorized();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: ${data['message']}'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
    } finally {
      if (mounted) {
        setState(() { _isProcessing = false; });
      }
    }
  }

  void _handleUnauthorized() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await HttpClient.clearCookies();
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
      appBar: AppBar(title: Text(widget.event['title'] ?? 'Detail Event')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Builder(builder: (context) { /* ... kode gambar ... */
              final String? imageName = widget.event['image_filename'];
              if (imageName == null || imageName.isEmpty) {
                return Container(height: 250, color: Colors.grey[300], child: Center(child: Icon(Icons.image_not_supported, size: 100, color: Colors.grey[600])));
              }
              final String imageUrl = '${AppConfig.apiBaseUrl}/uploads/$imageName';
              return Image.network(imageUrl, height: 250, width: double.infinity, fit: BoxFit.cover,
                loadingBuilder: (ctx, child, progress) => progress == null ? child : Container(height: 250, color: Colors.grey[300], child: const Center(child: CircularProgressIndicator())),
                errorBuilder: (ctx, err, stack) => Container(height: 250, color: Colors.grey[300], child: Center(child: Icon(Icons.broken_image, size: 100, color: Colors.grey[600]))),
              );
            }),
            Padding(padding: const EdgeInsets.all(16.0), child: Column( /* ... kode detail teks ... */
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.event['title'] ?? 'Nama Event Tidak Tersedia', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                InfoRow(icon: Icons.calendar_today_outlined, text: widget.event['date'] ?? '-'),
                const SizedBox(height: 8),
                InfoRow(icon: Icons.location_on_outlined, text: widget.event['location'] ?? '-'),
                const SizedBox(height: 24),
                const Text('Deskripsi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(widget.event['description'] ?? 'Deskripsi tidak tersedia.', style: const TextStyle(height: 1.5)),
              ],
            )),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _registrationStatusFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting || snapshot.hasError) {
              return ElevatedButton(
                onPressed: null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                    : const Text('Error Memeriksa Status'),
              );
            }

            final regStatus = snapshot.data!;
            final bool isButtonEnabled = regStatus['isEnabled'];
            final String buttonText = regStatus['text'];

            final VoidCallback? onPressedAction = isButtonEnabled ? _getFreeTicket : null;

            return ElevatedButton(
              onPressed: _isProcessing ? null : onPressedAction,
              child: _isProcessing
                  ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                  : Text(buttonText),
              style: ElevatedButton.styleFrom(
                backgroundColor: isButtonEnabled ? Colors.red : Colors.grey,
                foregroundColor: Colors.white,
              ),
            );
          },
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget { /* ... kode InfoRow ... */
  final IconData icon;
  final String text;
  const InfoRow({super.key, required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
        const SizedBox(width: 16),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 16))),
      ],
    );
  }
}