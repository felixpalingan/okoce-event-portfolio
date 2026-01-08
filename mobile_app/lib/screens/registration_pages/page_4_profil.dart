
import 'package:flutter/material.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/gestures.dart';

class Region {
  final String id;
  final String name;
  Region({required this.id, required this.name});

  factory Region.fromJson(Map<String, dynamic> json) {
    return Region(id: json['code'], name: json['name']);
  }
}

class Page4Profil extends StatefulWidget {
  final Function(String, String, String, bool) onNext;
  const Page4Profil({super.key, required this.onNext});

  @override
  State<Page4Profil> createState() => _Page4ProfilState();
}

class _Page4ProfilState extends State<Page4Profil> with AutomaticKeepAliveClientMixin {
  final _formKey = GlobalKey<FormState>();
  final _institutionController = TextEditingController();
  bool _hasBusiness = false;
  Region? _selectedProvince;
  Region? _selectedCity;
  bool _isAgreed = false;

  final GlobalKey<DropdownSearchState<Region>> _cityDropdownKey = GlobalKey<DropdownSearchState<Region>>();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _institutionController.dispose();
    super.dispose();
  }

  Future<List<Region>> _getRegions(String type, {String? provinceId}) async {
    String url;
    if (type == 'province') {
      url = "https://wilayah.id/api/provinces.json";
    } else {
      provinceId ??= _selectedProvince?.id;
      if (type == 'city' && provinceId == null) return [];
      url = "https://wilayah.id/api/regencies/$provinceId.json";
    }

    try {
      print("Fetching $type from: $url");
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = json.decode(response.body);
        final List data = jsonResponse['data'];

        return data.map((item) => Region.fromJson(item)).toList();
      } else {
        print("Error fetching $type: ${response.statusCode}");
      }
    } catch (e) {
      print("Exception fetching regions: $e");
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat data $type. Periksa koneksi internet.')),
        );
      }
    }
    return [];
  }

  void _showPrivacyPolicy() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, controller) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Text("Kebijakan Privasi & Ketentuan Pengguna",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: controller,
                      child: Text(
                        """
1. PENGUMPULAN DATA
Kami mengumpulkan data pribadi Anda berupa Nama, NIK (untuk verifikasi UMKM), Email, dan Nomor Telepon untuk keperluan operasional Event Organizer OK OCE.

2. PENGGUNAAN DATA
Data Anda digunakan untuk:
- Verifikasi keanggotaan.
- Pendaftaran event dan sertifikat.
- Analisis statistik partisipasi UMKM (secara anonim).

3. BERBAGI DATA
Kami tidak menjual data Anda. Data mungkin dibagikan kepada pihak ketiga (seperti Payment Gateway atau Dinas terkait) hanya jika diperlukan untuk transaksi atau kewajiban hukum.

4. HAK ANDA (UU PDP)
Anda berhak meminta penghapusan akun atau koreksi data kapan saja melalui menu Profil.

Dengan melanjutkan, Anda menyatakan data yang diisi adalah benar dan menyetujui pemrosesan data di atas.
                        """,
                        style: TextStyle(height: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Saya Mengerti"),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _submit() {
    FocusScope.of(context).unfocus();

    if (!_isAgreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Anda harus menyetujui Kebijakan Privasi untuk melanjutkan.')),
      );
      return;
    }

    if (_formKey.currentState!.validate()) {
      widget.onNext(
        _selectedProvince!.name,
        _selectedCity!.name,
        _institutionController.text,
        _hasBusiness,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final appBarHeight = Scaffold.of(context).appBarMaxHeight ?? kToolbarHeight;
    final screenPadding = MediaQuery.of(context).padding;
    final availableHeight = MediaQuery.of(context).size.height - appBarHeight - screenPadding.top - screenPadding.bottom - 48;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: SizedBox(
            height: availableHeight < 550 ? 550 : availableHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Text(
                  'Satu langkah terakhir!',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                DropdownSearch<Region>(
                  asyncItems: (filter) => _getRegions('province'),
                  itemAsString: (item) => item.name,
                  selectedItem: _selectedProvince,
                  onChanged: (province) {
                    setState(() {
                      _selectedProvince = province;
                      _selectedCity = null;
                      _cityDropdownKey.currentState?.clear();
                    });
                  },
                  dropdownDecoratorProps: const DropDownDecoratorProps(
                      dropdownSearchDecoration: InputDecoration(
                          labelText: "Provinsi",
                          border: OutlineInputBorder()
                      )
                  ),
                  popupProps: PopupProps.menu(
                    showSearchBox: true,
                    searchFieldProps: TextFieldProps(decoration: InputDecoration(hintText: "Cari Provinsi...")),
                    itemBuilder: (context, item, isSelected) => ListTile(title: Text(item.name)),
                    emptyBuilder: (context, searchEntry) => const Center(child: Text("Provinsi tidak ditemukan")),
                  ),
                  validator: (v) => v == null ? 'Provinsi wajib dipilih' : null,
                ),

                const SizedBox(height: 16),

                DropdownSearch<Region>(
                  key: _cityDropdownKey,
                  asyncItems: (filter) => _getRegions('city'),
                  itemAsString: (item) => item.name,
                  selectedItem: _selectedCity,
                  onChanged: (city) => setState(() => _selectedCity = city),
                  enabled: _selectedProvince != null,
                  dropdownDecoratorProps: DropDownDecoratorProps(
                      dropdownSearchDecoration: InputDecoration(
                          labelText: "Kabupaten/Kota",
                          border: const OutlineInputBorder(),
                          hintText: _selectedProvince == null ? "Pilih provinsi dahulu" : null
                      )
                  ),
                  popupProps: PopupProps.menu(
                    showSearchBox: true,
                    searchFieldProps: TextFieldProps(decoration: InputDecoration(hintText: "Cari Kota...")),
                    itemBuilder: (context, item, isSelected) => ListTile(title: Text(item.name)),
                    emptyBuilder: (context, searchEntry) => const Center(child: Text("Kota tidak ditemukan")),
                  ),
                  validator: (v) => v == null ? 'Kabupaten/Kota wajib dipilih' : null,
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller: _institutionController,
                  decoration: const InputDecoration(
                    labelText: 'Asal Instansi (Opsional)',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                ),

                SwitchListTile(
                  title: const Text('Sudah punya usaha?'),
                  value: _hasBusiness,
                  onChanged: (val) => setState(() => _hasBusiness = val),
                  contentPadding: EdgeInsets.zero,
                  activeColor: Theme.of(context).colorScheme.secondary,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 24),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: Checkbox(
                        value: _isAgreed,
                        onChanged: (val) {
                          setState(() {
                            _isAgreed = val ?? false;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          text: 'Saya menyetujui ',
                          style: TextStyle(color: Colors.black, fontSize: 14),
                          children: [
                            TextSpan(
                              text: 'Syarat & Ketentuan',
                              style: TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = _showPrivacyPolicy,
                            ),
                            TextSpan(
                              text: ' serta Kebijakan Privasi OK OCE.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: _isAgreed ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isAgreed ? null : Colors.grey,
                  ),
                  child: const Text('Selesai & Daftar'),
                ),

                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}