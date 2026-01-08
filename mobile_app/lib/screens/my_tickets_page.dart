
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:eventit/config.dart';
import 'package:eventit/screens/qr_display_page.dart';
import 'package:eventit/utils/http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eventit/screens/login_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:eventit/screens/test_screen.dart';

class MyTicketsPage extends StatefulWidget {
  const MyTicketsPage({super.key});

  @override
  State<MyTicketsPage> createState() => _MyTicketsPageState();
}

class _MyTicketsPageState extends State<MyTicketsPage> {
  Future<List<dynamic>> _fetchMyTickets() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    int? userId = prefs.getInt('user_id');
    if (userId == null) {
      _handleUnauthorized();
      return [];
    }

    try {
      final response = await HttpClient.get('/api/users/$userId/tickets');

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Unauthorized');
      } else {
        throw Exception('Gagal memuat tiket (${response.statusCode})');
      }
    } catch (e) {
      if (e.toString().contains('Unauthorized')) {
        _handleUnauthorized();
        return [];
      }
      throw Exception('Error: ${e.toString()}');
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
      appBar: AppBar(title: const Text('Tiket Saya')),
      body: FutureBuilder<List<dynamic>>(
        future: _fetchMyTickets(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: ElevatedButton(onPressed: () => setState(() {}), child: const Text("Coba Lagi")));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async => setState(() {}),
              child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                    Icon(Icons.confirmation_number_outlined, size: 80, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    const Center(child: Text('Anda belum memiliki tiket.', style: TextStyle(fontSize: 18, color: Colors.grey)))
                  ]
              ),
            );
          }

          final tickets = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: tickets.length,
              itemBuilder: (context, index) {
                final ticket = tickets[index];

                String status = ticket['status'] ?? 'READY';
                String statusLabel = ticket['status_label'] ?? 'Tersedia';
                String eventLocation = ticket['event_location'] ?? 'Offline';
                bool isEventOnline = eventLocation.contains('Online');

                Color chipColor = Colors.green;
                if (status == 'PRE_TEST') chipColor = Colors.orange;
                else if (status == 'POST_TEST') chipColor = Colors.blue;
                else if (status == 'DONE') chipColor = Colors.grey;

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: ListTile(
                    leading: Icon(
                      isEventOnline ? Icons.videocam_outlined : Icons.qr_code_scanner_outlined,
                      color: Theme.of(context).colorScheme.primary,
                      size: 30,
                    ),
                    title: Text(ticket['event_title'] ?? 'Event', style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(ticket['event_date'] ?? '-'),

                    trailing: Chip(
                      label: Text(statusLabel, style: const TextStyle(color: Colors.white, fontSize: 12)),
                      backgroundColor: chipColor,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      visualDensity: VisualDensity.compact,
                    ),

                    onTap: () {
                      if (status == 'READY') {
                        if (isEventOnline) {
                          _joinOnlineEvent(context, ticket['event_id'], ticket['ticket_code']);
                        } else {
                          _showQrCode(context, ticket['ticket_code'], ticket['event_title']);
                        }
                      } else if (status == 'PRE_TEST') {
                        _handleTestFlow(ticket['event_id'], 'Pre-Test');
                      } else if (status == 'POST_TEST') {
                        _handleTestFlow(ticket['event_id'], 'Post-Test');
                      } else if (status == 'DONE') {
                        _handleTestFlow(ticket['event_id'], 'Show-Result');
                      }
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _showQrCode(BuildContext context, String ticketCode, String eventTitle) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String userName = prefs.getString('user_name') ?? 'Pengguna';
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => QrDisplayPage(ticketCode: ticketCode, eventTitle: eventTitle, userName: userName),
    )).then((_) => setState(() {}));
  }

  Future<void> _joinOnlineEvent(BuildContext context, int eventId, String ticketCode) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konfirmasi Kehadiran'),
        content: const Text('Anda akan otomatis ter-check-in. Lanjutkan?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Ya, Gabung')),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final checkinResponse = await HttpClient.post('/api/checkin', {'ticket_code': ticketCode});
      if (!mounted) return;

      if (checkinResponse.statusCode == 200) {
        final urlResponse = await HttpClient.get('/api/events/$eventId/join_url');
        if (urlResponse.statusCode == 200) {
          final data = json.decode(urlResponse.body);
          await launchUrl(Uri.parse(data['join_url']), mode: LaunchMode.externalApplication);
          setState(() {});
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal mengambil link event.')));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal check-in.')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _handleTestFlow(int eventId, String actionType) async {

    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));

    try {
      final response = await HttpClient.get('/api/events/$eventId/test/status');
      if (!mounted) return;
      Navigator.of(context).pop();

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final status = data['status'];

        if (status == 'PRE_TEST_NEEDED') {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => TestScreen(eventId: eventId, testType: "Pre-Test"),
          )).then((_) => setState(() {}));
        }
        else if (status == 'POST_TEST_LOCKED') {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Post-Test belum dibuka. Tunggu hingga akhir acara."),
            backgroundColor: Colors.orange,
          ));
        }
        else if (status == 'POST_TEST_AVAILABLE') {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => TestScreen(eventId: eventId, testType: "Post-Test"),
          )).then((_) => setState(() {}));
        }
        else if (status == 'COMPLETED') {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("Hasil Tes Anda"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Pre-Test: ${data['pre_score']}"),
                  const SizedBox(height: 8),
                  Text("Post-Test: ${data['post_score']}"),
                  const Divider(),
                  const Text("Terima kasih telah berpartisipasi!", style: TextStyle(fontStyle: FontStyle.italic)),
                ],
              ),
              actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Tutup"))],
            ),
          );
        }
      }
    } catch (e) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}