
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:eventit/config.dart';
import 'package:eventit/screens/event_detail_page.dart';
import 'package:eventit/screens/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eventit/utils/http_client.dart';

class EventListPage extends StatefulWidget {
  const EventListPage({super.key});

  @override
  State<EventListPage> createState() => _EventListPageState();
}

class _EventListPageState extends State<EventListPage> {
  late Future<List<dynamic>> _eventsFuture;

  @override
  void initState() {
    super.initState();
    _eventsFuture = _fetchEvents();
  }

  Future<List<dynamic>> _fetchEvents() async {
    try {
      final response = await HttpClient.get('/api/events');

      print('--- DEBUG: Response from /api/events ---');
      print('Status Code: ${response.statusCode}');

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 401 || response.statusCode == 422) {
        _handleUnauthorized();
        return [];
      } else {
        throw Exception('Gagal memuat event (${response.statusCode})');
      }
    } catch (e) {
      print('Error fetching events: $e');
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
        title: const Text('Daftar Event'),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _eventsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          else if (snapshot.hasError) {
            if (snapshot.error.toString().contains('Unauthorized')) {
              return const Center(child: Text('Sesi berakhir, mengarahkan ke login...'));
            }
            return Center(child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error memuat data: ${snapshot.error}', textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  ElevatedButton(onPressed: (){
                    setState(() { _eventsFuture = _fetchEvents(); });
                  }, child: const Text("Coba Lagi"))
                ],
              ),
            ));
          }
          else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async => setState(() { _eventsFuture = _fetchEvents(); }),
              child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 150),
                    Center(child: Text('Tidak ada event tersedia saat ini.'))
                  ]
              ),
            );
          }

          final events = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _eventsFuture = _fetchEvents();
              });
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: events.length,
              itemBuilder: (context, index) {
                final event = events[index];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  elevation: 3,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => EventDetailPage(event: event),
                      )).then((result) {
                        if (result == true) {
                          setState(() {
                            _eventsFuture = _fetchEvents();
                          });
                        }
                      });
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Builder(
                          builder: (context) {
                            final String? imageName = event['image_filename'];
                            if (imageName == null || imageName.isEmpty) {
                              return Container(height: 180, color: Colors.grey[300], child: Center(child: Icon(Icons.image_not_supported, size: 50, color: Colors.grey[600])));
                            }
                            final String imageUrl = '${AppConfig.apiBaseUrl}/uploads/$imageName';
                            return Image.network(
                              imageUrl, height: 180, width: double.infinity, fit: BoxFit.cover,
                              loadingBuilder: (ctx, child, progress) => progress == null ? child : Container(height: 180, color: Colors.grey[300], child: const Center(child: CircularProgressIndicator())),
                              errorBuilder: (ctx, err, stack) => Container(height: 180, color: Colors.grey[300], child: Center(child: Icon(Icons.broken_image, size: 50, color: Colors.grey[600]))),
                            );
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(event['title'] ?? 'Nama Event Tidak Tersedia', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              InfoRow(icon: Icons.calendar_today_outlined, text: event['date'] ?? '-'),
                              const SizedBox(height: 4),
                              InfoRow(icon: Icons.location_on_outlined, text: event['location'] ?? '-'),
                              const SizedBox(height: 8),
                              Text(
                                (event['price'] ?? 0) == 0 ? 'GRATIS' : 'Rp ${event['price']}',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const InfoRow({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

