
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:eventit/config.dart';
import 'package:eventit/utils/http_client.dart';
import 'package:eventit/screens/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:http/http.dart' as http;

class Region {
  final String id;
  final String name;
  Region({required this.id, required this.name});
  factory Region.fromJson(Map<String, dynamic> json) => Region(id: json['id'], name: json['name']);
}

final List<String> kBusinessTypes = [ 'Agen Wisata Pejalanan (AWP)', 'Agrobisnis', 'Budidaya Perikanan', 'Budidaya Pertanian', 'Elektronik', 'Fashion', 'Jasa', 'Kerajinan / Souvenir', 'Makanan dan Minuman', 'Menjahit / Bordir', 'Olahan Perikanan', 'Olahan Pertanian', 'Olahan Peternakan', 'Otomotif', 'Pendidikan', 'Peternakan', 'Produksi Sabun Rumah Tangga dan Alat Kesehatan', 'Pulsa', 'Sablon dan Desain Grafis', 'Seni mUsik / Rupa / Teater / Tari', 'Service Elektronik', 'Service Kendaraan', 'Steam Motor / Mobil', 'Tata Rias, Pengantin dan Salon', 'Teknologi', 'Warung Sembako' ];
final List<String> kPremiseStatusOptions = [ 'Milik Keluarga', 'Milik Sendiri', 'Pinjaman', 'Sewa' ];
final List<String> kMarketplaceOptions = [ 'Tokopedia', 'Shopee', 'Bukalapak', 'Lazada', 'Blibli', 'JD.ID', 'OLX', 'Pasar Sedekah', 'okocemall', 'Facebook', 'Instagram', 'Twitter', 'Tiktok', 'Youtube', 'Whatsapp', 'Telegram', 'Website', 'Lainnya' ];
final List<String> kLicenseTypeOptions = [ 'NIB', 'IUMK', 'PIRT', 'Halal', 'BPOM', 'HKI', 'SNI', 'PKRT', 'Lainnya' ];
final List<String> kLegalEntityOptions = [ 'Belum Memiliki', 'Perseorangan', 'PT', 'CV', 'Koperasi', 'PT (Perseorangan)' ];
final List<String> kOmzetOptions = [ '< Rp 2.000.000.000', 'Rp 2.000.000.000 - Rp 15.000.000.000', 'Rp 15.000.000.000 - Rp 50.000.000.000' ];
final List<String> kEmployeeOptions = [ '1 Orang', '2 - 10 Orang', '11 - 19 Orang', '20 - 99 Orang', '> 100 Orang' ];
final List<String> kFinanceAppOptions = [ 'Chatat', 'Eresto', 'iPOS', 'Lunapos', 'OK Gan', 'Zahir', 'Lainnya' ];
final List<String> kFunderOptions = [ 'BANK', 'Koperasi', 'Fintech', 'Hibah', 'Komunitas', 'BUMN', 'BUMD', 'Lainnya' ];

class UmkmFormScreen extends StatefulWidget {
  final int? businessId;
  const UmkmFormScreen({super.key, this.businessId});

  @override
  State<UmkmFormScreen> createState() => _UmkmFormScreenState();
}

class _UmkmFormScreenState extends State<UmkmFormScreen> {
  final PageController _pageController = PageController();
  final _formKeyP1 = GlobalKey<FormState>();
  final _formKeyP2 = GlobalKey<FormState>();
  final _formKeyP3 = GlobalKey<FormState>();

  int _currentPage = 0;
  bool _isLoading = false;
  bool get _isEditMode => widget.businessId != null;
  String? _errorMessage;

  final _nameController = TextEditingController();
  String? _businessType;
  bool _addressSameAsHome = false;
  Region? _selectedProvince;
  Region? _selectedCity;
  Region? _selectedDistrict;
  Region? _selectedVillage;
  final _provinceController = TextEditingController();
  final _cityController = TextEditingController();
  final _addressDistrictController = TextEditingController();
  final _addressVillageController = TextEditingController();
  final _rtController = TextEditingController();
  final _rwController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _addressDetailController = TextEditingController();
  String? _premiseStatus;
  String? _marketplaceType;
  final _marketplaceUrlController = TextEditingController();
  bool _hasLicense = false;
  String? _licenseType;
  final _licenseNumberController = TextEditingController();
  String? _legalEntity;
  final _financeYearController = TextEditingController();
  String? _omzetRange;
  final _profitController = TextEditingController();
  final _assetController = TextEditingController();
  String? _employeeCount;
  bool _hasNpwp = false;
  final _npwpNumberController = TextEditingController();
  final _npwpReceiptController = TextEditingController();
  final _npwpYearController = TextEditingController();
  final _npwpDateController = TextEditingController();
  String _financialReportType = 'Manual';
  String? _financialReportApp;
  bool _reportLabaRugi = false;
  bool _reportNeraca = false;
  bool _reportArusKas = false;
  bool _hasFunding = false;
  String? _funderType;
  final _funderNameController = TextEditingController();
  final _fundingAmountController = TextEditingController();
  final _fundingDateController = TextEditingController();
  final _installmentDateController = TextEditingController();
  final _durationMonthsController = TextEditingController();
  final _businessPhoneController = TextEditingController();
  final _businessEmailController = TextEditingController();
  final _opSinceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (_isEditMode) {
      _fetchBusinessDetails();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _provinceController.dispose();
    _cityController.dispose();
    _addressDistrictController.dispose();
    _addressVillageController.dispose();
    _rtController.dispose();_rwController.dispose();_postalCodeController.dispose();
    _addressDetailController.dispose();_marketplaceUrlController.dispose();
    _licenseNumberController.dispose();_financeYearController.dispose();
    _profitController.dispose();_assetController.dispose();
    _npwpNumberController.dispose();_npwpReceiptController.dispose();
    _npwpYearController.dispose();_npwpDateController.dispose();
    _funderNameController.dispose();_fundingAmountController.dispose();
    _fundingDateController.dispose();_installmentDateController.dispose();
    _durationMonthsController.dispose();_businessPhoneController.dispose();
    _businessEmailController.dispose();_opSinceController.dispose();
    super.dispose();
  }

  void _nextPage() {
    FocusScope.of(context).unfocus();
    if (_currentPage == 0 && !_formKeyP1.currentState!.validate()) return;
    if (_currentPage == 1 && !_formKeyP2.currentState!.validate()) return;
    if (_currentPage == 2 && !_formKeyP3.currentState!.validate()) return;

    if (_currentPage == 2) {
      _submitForm();
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeIn,
      );
    }
  }
  void _previousPage() {
    FocusScope.of(context).unfocus();
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeIn,
    );
  }

  Future<List<Region>> _getRegions(String type, {String? parentId}) async {
    String url;
    if (type == 'province') {
      url = "https://www.emsifa.com/api-wilayah-indonesia/api/provinces.json";
    } else if (type == 'city' && parentId != null) {
      url = "https://www.emsifa.com/api-wilayah-indonesia/api/regencies/$parentId.json";
    } else if (type == 'district' && parentId != null) {
      url = "https://www.emsifa.com/api-wilayah-indonesia/api/districts/$parentId.json";
    } else if (type == 'village' && parentId != null) {
      url = "https://www.emsifa.com/api-wilayah-indonesia/api/villages/$parentId.json";
    } else {
      return [];
    }
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        return data.map((item) => Region.fromJson(item)).toList();
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memuat data wilayah: $e'), backgroundColor: Colors.red));
    }
    return [];
  }

  Future<void> _fetchBusinessDetails() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final response = await HttpClient.get('/api/user/businesses/${widget.businessId}');
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _nameController.text = data['business_name'] ?? '';
          _businessType = data['business_type'];
          _addressSameAsHome = data['address_same_as_home'] ?? false;

          _provinceController.text = data['address_province'] ?? '';
          _cityController.text = data['address_city'] ?? '';
          _addressDistrictController.text = data['address_district'] ?? '';
          _addressVillageController.text = data['address_village'] ?? '';

          _rtController.text = data['address_rt'] ?? '';
          _rwController.text = data['address_rw'] ?? '';
          _postalCodeController.text = data['address_postal_code'] ?? '';
          _addressDetailController.text = data['address_detail'] ?? '';
          _premiseStatus = data['premise_status'];
          _marketplaceType = data['marketplace_type'];
          _marketplaceUrlController.text = data['url'] ?? '';
          _hasLicense = data['has_license'] ?? false;
          _licenseType = data['license_type'];
          _licenseNumberController.text = data['license_number'] ?? '';
          _legalEntity = data['legal_entity'];
          _financeYearController.text = data['finance_year'] ?? '';
          _omzetRange = data['omzet_range'];
          _profitController.text = (data['profit'] ?? '').toString();
          _assetController.text = (data['asset_value'] ?? '').toString();
          _employeeCount = data['employee_count'];
          _hasNpwp = data['has_npwp'] ?? false;
          _npwpNumberController.text = data['npwp_number'] ?? '';
          _npwpReceiptController.text = data['report_receipt_number'] ?? '';
          _npwpYearController.text = data['npwp_year'] ?? '';
          _npwpDateController.text = data['submission_date'] ?? '';
          _financialReportType = data['financial_report_type'] ?? 'Manual';
          _financialReportApp = data['financial_report_app'];
          _reportLabaRugi = data['report_laba_rugi'] ?? false;
          _reportNeraca = data['report_neraca'] ?? false;
          _reportArusKas = data['report_arus_kas'] ?? false;
          _hasFunding = data['has_funding'] ?? false;
          _funderType = data['funder_type'];
          _funderNameController.text = data['funder_name'] ?? '';
          _fundingAmountController.text = (data['amount'] ?? '').toString();
          _fundingDateController.text = data['received_date'] ?? '';
          _installmentDateController.text = data['installment_start_date'] ?? '';
          _durationMonthsController.text = (data['duration_months'] ?? '').toString();
          _businessPhoneController.text = data['business_phone'] ?? '';
          _businessEmailController.text = data['business_email'] ?? '';
          _opSinceController.text = data['operating_since'] ?? '';
        });
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        _handleUnauthorized();
      } else {
        throw Exception("Gagal memuat data UMKM (${response.statusCode})");
      }
    } catch (e) {
      if (e.toString().contains('Unauthorized')) { _handleUnauthorized(); }
      else if (mounted) { setState(() { _errorMessage = e.toString(); }); }
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _submitForm() async {

    setState(() { _isLoading = true; });

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      int? userId = prefs.getInt('user_id');
      if (userId == null) throw Exception("Unauthorized");

      final Map<String, dynamic> body = {
        'business_id': widget.businessId,
        'business_name': _nameController.text,
        'business_type': _businessType,
        'address_same_as_home': _addressSameAsHome,
        'address_province': _selectedProvince?.name ?? _provinceController.text,
        'address_city': _selectedCity?.name ?? _cityController.text,
        'address_district': _addressDistrictController.text,
        'address_village': _addressVillageController.text,
        'address_rt': _rtController.text,
        'address_rw': _rwController.text,
        'address_postal_code': _postalCodeController.text,
        'address_detail': _addressDetailController.text,
        'premise_status': _premiseStatus,
        'marketplace_type': _marketplaceType,
        'url': _marketplaceUrlController.text,
        'has_license': _hasLicense,
        'license_type': _licenseType,
        'license_number': _licenseNumberController.text,
        'legal_entity': _legalEntity,
        'finance_year': _financeYearController.text,
        'omzet_range': _omzetRange,
        'profit': int.tryParse(_profitController.text),
        'asset_value': int.tryParse(_assetController.text),
        'employee_count': _employeeCount,
        'has_npwp': _hasNpwp,
        'npwp_number': _npwpNumberController.text,
        'report_receipt_number': _npwpReceiptController.text,
        'npwp_year': _npwpYearController.text,
        'submission_date': _npwpDateController.text,
        'financial_report_type': _financialReportType,
        'financial_report_app': _financialReportApp,
        'report_laba_rugi': _reportLabaRugi,
        'report_neraca': _reportNeraca,
        'report_arus_kas': _reportArusKas,
        'has_funding': _hasFunding,
        'funder_type': _funderType,
        'funder_name': _funderNameController.text,
        'amount': int.tryParse(_fundingAmountController.text),
        'received_date': _fundingDateController.text,
        'installment_start_date': _installmentDateController.text,
        'duration_months': int.tryParse(_durationMonthsController.text),
        'business_phone': _businessPhoneController.text,
        'business_email': _businessEmailController.text,
        'operating_since': _opSinceController.text,
      };

      final response = await HttpClient.post('/api/user/businesses/submit', body);

      if (!mounted) return;
      final data = json.decode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message']), backgroundColor: Colors.green),
        );
        Navigator.of(context).pop(true);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        _handleUnauthorized();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: ${data['message']}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      print("Error submitting form: $e");
      if (e.toString().contains('Unauthorized')) { _handleUnauthorized(); }
      else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() { _isLoading = false; });
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
    final List<Widget> pages = [
      _buildPageInfoDasar(),
      _buildPageAlamat(),
      _buildPageLegalitasKeuanganKontak(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit Data UMKM' : 'Tambah Data UMKM'),
        leading: _currentPage == 0
            ? IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop())
            : IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isLoading ? null : _previousPage,
        ),
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(10.0),
            child: Opacity(
              opacity: _isLoading ? 0.5 : 1.0,
              child: LinearProgressIndicator(
                value: (_currentPage + 1) / pages.length,
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
            onPageChanged: (page) => setState(() => _currentPage = page),
            children: pages,
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white))),
            ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          onPressed: _isLoading ? null : _nextPage,
          child: Text(_currentPage == pages.length - 1 ? 'Simpan Data' : 'Lanjut'),
        ),
      ),
    );
  }

  Widget _buildPageInfoDasar() {
    return Form(
      key: _formKeyP1,
      child: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Text('Informasi Dasar Usaha', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: 'Nama Usaha *', border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? 'Wajib diisi' : null),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _businessType,
            hint: const Text('Jenis Usaha *'),
            isExpanded: true,
            items: kBusinessTypes.map((val) => DropdownMenuItem(value: val, child: Text(val, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (val) => setState(() => _businessType = val),
            validator: (v) => v == null ? 'Wajib dipilih' : null,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ],
      ),
    );
  }

  Widget _buildPageAlamat() {
    return Form(
      key: _formKeyP2,
      child: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Text('Alamat Usaha', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
          CheckboxListTile(
            title: const Text('Alamat usaha sama dengan alamat rumah?'),
            value: _addressSameAsHome,
            onChanged: (val) => setState(() => _addressSameAsHome = val ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          if (!_addressSameAsHome) ...[
            const SizedBox(height: 16),
            TextFormField(controller: _provinceController, decoration: const InputDecoration(labelText: 'Provinsi *', border: OutlineInputBorder()), validator: (v) => !_addressSameAsHome && v!.isEmpty ? 'Wajib diisi' : null),
            const SizedBox(height: 16),
            TextFormField(controller: _cityController, decoration: const InputDecoration(labelText: 'Kabupaten/Kota *', border: OutlineInputBorder()), validator: (v) => !_addressSameAsHome && v!.isEmpty ? 'Wajib diisi' : null),
            const SizedBox(height: 16),
            TextFormField(controller: _addressDistrictController, decoration: const InputDecoration(labelText: 'Kecamatan *', border: OutlineInputBorder()), validator: (v) => !_addressSameAsHome && v!.isEmpty ? 'Wajib diisi' : null),
            const SizedBox(height: 16),
            TextFormField(controller: _addressVillageController, decoration: const InputDecoration(labelText: 'Kelurahan *', border: OutlineInputBorder()), validator: (v) => !_addressSameAsHome && v!.isEmpty ? 'Wajib diisi' : null),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: TextFormField(controller: _rtController, decoration: const InputDecoration(labelText: 'RT', border: OutlineInputBorder()), keyboardType: TextInputType.number)),
              const SizedBox(width: 16),
              Expanded(child: TextFormField(controller: _rwController, decoration: const InputDecoration(labelText: 'RW', border: OutlineInputBorder()), keyboardType: TextInputType.number)),
            ]),
            const SizedBox(height: 16),
            TextFormField(controller: _postalCodeController, decoration: const InputDecoration(labelText: 'Kode Pos', border: OutlineInputBorder()), keyboardType: TextInputType.number),
            const SizedBox(height: 16),
            TextFormField(controller: _addressDetailController, decoration: const InputDecoration(labelText: 'Alamat (Nama Jalan, No. Rumah)', border: OutlineInputBorder()), maxLines: 3),
          ],
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            value: _premiseStatus,
            hint: const Text('Status Tempat Usaha *'),
            isExpanded: true,
            items: kPremiseStatusOptions.map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(),
            onChanged: (val) => setState(() => _premiseStatus = val),
            validator: (v) => v == null ? 'Wajib dipilih' : null,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          Text('Alamat Usaha Online (Fase 1: 1 entri)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _marketplaceType,
            hint: const Text('Marketplace (Opsional)'),
            isExpanded: true,
            items: kMarketplaceOptions.map((val) => DropdownMenuItem(value: val, child: Text(val, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (val) => setState(() => _marketplaceType = val),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          TextFormField(controller: _marketplaceUrlController, decoration: const InputDecoration(labelText: 'Link URL (Opsional)', border: OutlineInputBorder()), keyboardType: TextInputType.url),
        ],
      ),
    );
  }

  Widget _buildPageLegalitasKeuanganKontak() {
    return Form(
      key: _formKeyP3,
      child: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Text('Kontak & Operasional', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          TextFormField(controller: _businessPhoneController, decoration: const InputDecoration(labelText: 'Ponsel (Kontak Usaha) *', border: OutlineInputBorder()), keyboardType: TextInputType.phone, validator: (v) => v!.isEmpty ? 'Wajib diisi' : null),
          const SizedBox(height: 16),
          TextFormField(controller: _businessEmailController, decoration: const InputDecoration(labelText: 'Email Perusahaan *', border: OutlineInputBorder()), keyboardType: TextInputType.emailAddress, validator: (v) => v!.isEmpty ? 'Wajib diisi' : null),
          const SizedBox(height: 16),
          TextFormField(controller: _opSinceController,
              decoration: const InputDecoration(labelText: 'Mulai Beroperasi (Tgl/Tahun) *', border: OutlineInputBorder(), hintText: 'cth: 2020 atau 2020-01-15'),
              keyboardType: TextInputType.text,
              validator: (v) => v!.isEmpty ? 'Wajib diisi' : null
          ),

          const SizedBox(height: 24),
          Text('Legalitas & Keuangan', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          Text('Perizinan *', style: Theme.of(context).textTheme.titleMedium),
          Row(children: [Expanded(child: RadioListTile<bool>(title: const Text('Sudah Punya'), value: true, groupValue: _hasLicense, onChanged: (v) => setState(()=>_hasLicense=v!))), Expanded(child: RadioListTile<bool>(title: const Text('Belum'), value: false, groupValue: _hasLicense, onChanged: (v) => setState(()=>_hasLicense=v!)))]),
          if (_hasLicense) ...[
            DropdownButtonFormField<String>(value: _licenseType, hint: const Text('Jenis Perizinan (1 entri)'), isExpanded: true, items: kLicenseTypeOptions.map((val) => DropdownMenuItem(value: val, child: Text(val, overflow: TextOverflow.ellipsis))).toList(), onChanged: (val) => setState(() => _licenseType = val), decoration: const InputDecoration(border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextFormField(controller: _licenseNumberController, decoration: const InputDecoration(labelText: 'Nomor Perizinan (Opsional)', border: OutlineInputBorder())),
          ],
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(value: _legalEntity, hint: const Text('Badan Usaha (Legalitas) *'), isExpanded: true, items: kLegalEntityOptions.map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(), onChanged: (val) => setState(() => _legalEntity = val), validator: (v) => v == null ? 'Wajib dipilih' : null, decoration: const InputDecoration(border: OutlineInputBorder())),
          const SizedBox(height: 24),
          Text('Omzet & Tenaga Kerja (Data Terakhir)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          TextFormField(controller: _financeYearController, decoration: const InputDecoration(labelText: 'Tahun Data (cth: 2024) *', border: OutlineInputBorder()), keyboardType: TextInputType.number, validator: (v) => v!.isEmpty ? 'Wajib diisi' : null),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(value: _omzetRange, hint: const Text('Omzet Tahunan *'), isExpanded: true, items: kOmzetOptions.map((val) => DropdownMenuItem(value: val, child: Text(val, overflow: TextOverflow.ellipsis, maxLines: 2))).toList(), onChanged: (val) => setState(() => _omzetRange = val), validator: (v) => v == null ? 'Wajib dipilih' : null, decoration: const InputDecoration(border: OutlineInputBorder())),
          const SizedBox(height: 16),
          TextFormField(controller: _profitController, decoration: const InputDecoration(labelText: 'Total Profit (Opsional)', prefixText: 'Rp. ', border: OutlineInputBorder()), keyboardType: TextInputType.number),
          const SizedBox(height: 16),
          TextFormField(controller: _assetController, decoration: const InputDecoration(labelText: 'Nilai Aset (Opsional)', prefixText: 'Rp. ', border: OutlineInputBorder()), keyboardType: TextInputType.number),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(value: _employeeCount, hint: const Text('Jumlah Tenaga Kerja *'), isExpanded: true, items: kEmployeeOptions.map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(), onChanged: (val) => setState(() => _employeeCount = val), validator: (v) => v == null ? 'Wajib dipilih' : null, decoration: const InputDecoration(border: OutlineInputBorder())),
          const SizedBox(height: 24),
          Text('NPWP & Pajak *', style: Theme.of(context).textTheme.titleMedium),
          Row(children: [Expanded(child: RadioListTile<bool>(title: const Text('Sudah Punya'), value: true, groupValue: _hasNpwp, onChanged: (v) => setState(()=>_hasNpwp=v!))), Expanded(child: RadioListTile<bool>(title: const Text('Belum'), value: false, groupValue: _hasNpwp, onChanged: (v) => setState(()=>_hasNpwp=v!)))]),
          if (_hasNpwp) ...[
            TextFormField(controller: _npwpNumberController, decoration: const InputDecoration(labelText: 'No. NPWP (Opsional)', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextFormField(controller: _npwpReceiptController, decoration: const InputDecoration(labelText: 'No. Tanda Terima Laporan (Opsional)', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextFormField(controller: _npwpYearController, decoration: const InputDecoration(labelText: 'Tahun Lapor (Opsional)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
            const SizedBox(height: 16),
            TextFormField(controller: _npwpDateController, decoration: const InputDecoration(labelText: 'Tgl Penyampaian (Opsional)', border: OutlineInputBorder(), hintText: 'YYYY-MM-DD'), keyboardType: TextInputType.datetime),
          ],
          const SizedBox(height: 24),
          Text('Laporan Keuangan *', style: Theme.of(context).textTheme.titleMedium),
          Row(children: [Expanded(child: RadioListTile<String>(title: const Text('Manual'), value: 'Manual', groupValue: _financialReportType, onChanged: (v) => setState(()=>_financialReportType=v!))), Expanded(child: RadioListTile<String>(title: const Text('Aplikasi'), value: 'Aplikasi', groupValue: _financialReportType, onChanged: (v) => setState(()=>_financialReportType=v!)))]),
          if (_financialReportType == 'Aplikasi')
            DropdownButtonFormField<String>(value: _financialReportApp, hint: const Text('Pilih Aplikasi'), isExpanded: true, items: kFinanceAppOptions.map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(), onChanged: (val) => setState(() => _financialReportApp = val), decoration: const InputDecoration(border: OutlineInputBorder())),
          const SizedBox(height: 8),
          CheckboxListTile(title: const Text('Laporan Laba Rugi'), value: _reportLabaRugi, onChanged: (v) => setState(()=>_reportLabaRugi=v!), controlAffinity: ListTileControlAffinity.leading, contentPadding: EdgeInsets.zero),
          CheckboxListTile(title: const Text('Laporan Neraca'), value: _reportNeraca, onChanged: (v) => setState(()=>_reportNeraca=v!), controlAffinity: ListTileControlAffinity.leading, contentPadding: EdgeInsets.zero),
          CheckboxListTile(title: const Text('Laporan Arus Kas'), value: _reportArusKas, onChanged: (v) => setState(()=>_reportArusKas=v!), controlAffinity: ListTileControlAffinity.leading, contentPadding: EdgeInsets.zero),
          const SizedBox(height: 24),
          Text('Akses Pemodalan *', style: Theme.of(context).textTheme.titleMedium),
          Row(children: [Expanded(child: RadioListTile<bool>(title: const Text('Sudah Punya'), value: true, groupValue: _hasFunding, onChanged: (v) => setState(()=>_hasFunding=v!))), Expanded(child: RadioListTile<bool>(title: const Text('Belum'), value: false, groupValue: _hasFunding, onChanged: (v) => setState(()=>_hasFunding=v!)))]),
          if (_hasFunding) ...[
            DropdownButtonFormField<String>(value: _funderType, hint: const Text('Jenis Pemodal (1 entri)'), isExpanded: true, items: kFunderOptions.map((val) => DropdownMenuItem(value: val, child: Text(val, overflow: TextOverflow.ellipsis))).toList(), onChanged: (val) => setState(() => _funderType = val), decoration: const InputDecoration(border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextFormField(controller: _funderNameController, decoration: const InputDecoration(labelText: 'Nama Pemodal (Opsional)', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextFormField(controller: _fundingAmountController, decoration: const InputDecoration(labelText: 'Jumlah Modal (Opsional)', prefixText: 'Rp. ', border: OutlineInputBorder()), keyboardType: TextInputType.number),
            const SizedBox(height: 16),
            TextFormField(controller: _fundingDateController, decoration: const InputDecoration(labelText: 'Tgl Terima Modal (Opsional)', border: OutlineInputBorder(), hintText: 'YYYY-MM-DD'), keyboardType: TextInputType.datetime),
            const SizedBox(height: 16),
            TextFormField(controller: _installmentDateController, decoration: const InputDecoration(labelText: 'Tgl Mulai Angsuran (Opsional)', border: OutlineInputBorder(), hintText: 'YYYY-MM-DD'), keyboardType: TextInputType.datetime),
            const SizedBox(height: 16),
            TextFormField(controller: _durationMonthsController, decoration: const InputDecoration(labelText: 'Jangka Waktu (Bulan) (Opsional)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
          ],
        ],
      ),
    );
  }
}