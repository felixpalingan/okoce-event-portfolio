
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:eventit/config.dart';
import 'package:eventit/utils/http_client.dart';
import 'package:eventit/screens/login_screen.dart';
import 'package:eventit/screens/umkm_form_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UmkmListScreen extends StatefulWidget {
  const UmkmListScreen({super.key});

  @override
  State<UmkmListScreen> createState() => _UmkmListScreenState();
}

class _UmkmListScreenState extends State<UmkmListScreen> {
  late Future<List<dynamic>> _businessesFuture;

  @override
  void initState() {
    super.initState();
    _businessesFuture = _fetchBusinesses();
  }

  Future<List<dynamic>> _fetchBusinesses() async {
    try {
      final response = await HttpClient.get('/api/user/businesses');

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Unauthorized');
      } else {
        throw Exception('Gagal memuat data UMKM (${response.statusCode})');
      }
    } catch (e) {
      print('Error fetching businesses: $e');
      if (e.toString().contains('Unauthorized')) {
        _handleUnauthorized();
        return [];
      }
      throw Exception('Error: ${e.toString()}');
    }
  }

  Future<void> _deleteBusiness(int businessId, String businessName) async {
    bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Konfirmasi Hapus'),
          content: Text('Apakah Anda yakin ingin menghapus data UMKM "$businessName"?\n\nData yang sudah dihapus tidak dapat dikembalikan.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Batal'),
              onPressed: () {
                Navigator.of(ctx).pop(false);
              },
            ),
            TextButton(
              child: const Text('Hapus', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(ctx).pop(true);
              },
            ),
          ],
        );
      },
    );

    if (confirmDelete != true) return;

    try {
      final response = await HttpClient.post(
        '/api/user/businesses/$businessId/delete',
        {},
      );

      if (!mounted) return;
      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message']), backgroundColor: Colors.green),
        );
        setState(() {
          _businessesFuture = _fetchBusinesses();
        });
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        _handleUnauthorized();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: ${data['message']}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (e.toString().contains('Unauthorized')) {
        _handleUnauthorized();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
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

  void _navigateToAddForm() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const UmkmFormScreen(businessId: null),
      ),
    ).then((result) {
      if (result == true) {
        setState(() {
          _businessesFuture = _fetchBusinesses();
        });
      }
    });
  }

  void _navigateToEditForm(int businessId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => UmkmFormScreen(businessId: businessId),
      ),
    ).then((result) {
      if (result == true) {
        setState(() {
          _businessesFuture = _fetchBusinesses();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data UMKM Saya'),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _businessesFuture,
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
                    setState(() { _businessesFuture = _fetchBusinesses(); });
                  }, child: const Text("Coba Lagi"))
                ],
              ),
            ));
          }
          else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async => setState(() { _businessesFuture = _fetchBusinesses(); }),
              child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24.0),
                      alignment: Alignment.center,
                      height: MediaQuery.of(context).size.height * 0.6,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.store_mall_directory_outlined, size: 80, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          const Text(
                            'Anda belum memiliki data UMKM',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Klik tombol + di bawah untuk menambahkan data usaha Anda.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ]
              ),
            );
          }

          final businesses = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => setState(() { _businessesFuture = _fetchBusinesses(); }),
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: businesses.length,
              itemBuilder: (context, index) {
                final business = businesses[index];
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    title: Text(business['business_name'] ?? 'Nama Usaha', style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(business['business_type'] ?? 'Jenis Usaha'),

                    onTap: () {
                      _navigateToEditForm(business['id']);
                    },

                    trailing: IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      tooltip: 'Hapus UMKM',
                      onPressed: () {
                        _deleteBusiness(
                            business['id'],
                            business['business_name'] ?? 'Usaha Ini'
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToAddForm,
        backgroundColor: Colors.red,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}