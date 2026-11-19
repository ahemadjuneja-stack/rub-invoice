import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../data/repo.dart';
import '../../services/access_service.dart';
import '../../widgets/widgets.dart';

/// Business Profile (Settings -> Business Profile).
///
/// Shows every detail captured at registration and lets the owner edit
/// everything that is NOT part of the Google login: Shop Name, Owner
/// Name, Mobile, City, Address, GST. The Gmail stays read-only.
/// Also holds the Business Logo / Signature images (used for branding,
/// stored locally and kept when the bill formats are extended).
class BusinessProfileScreen extends StatefulWidget {
  const BusinessProfileScreen({super.key});

  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  final _shopC = TextEditingController();
  final _ownerC = TextEditingController();
  final _mobileC = TextEditingController();
  final _cityC = TextEditingController();
  final _addrC = TextEditingController();
  final _gstC = TextEditingController();

  String _email = '';
  String _logoPath = '';
  String _signPath = '';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _shopC.dispose();
    _ownerC.dispose();
    _mobileC.dispose();
    _cityC.dispose();
    _addrC.dispose();
    _gstC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final info = AccessService.instance.account.value;
    final sp = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _shopC.text = info?.businessName ?? '';
      _ownerC.text = info?.ownerName ?? '';
      _mobileC.text = info?.mobile ?? info?.phone ?? '';
      _cityC.text = info?.city ?? '';
      _addrC.text = info?.address ?? '';
      _gstC.text = info?.gst ?? '';
      _email = info?.email ?? '';
      _logoPath = sp.getString('business_logo_path') ?? '';
      _signPath = sp.getString('business_signature_path') ?? '';
      _loading = false;
    });
  }

  Future<String?> _persistImage(String tmpPath, String name) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}${Platform.pathSeparator}business_assets');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final dst = File(
          '${dir.path}${Platform.pathSeparator}$name.jpg');
      await File(tmpPath).copy(dst.path);
      return dst.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickImage({required bool isLogo}) async {
    try {
      final x = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1200);
      if (x == null) return;
      final saved = await _persistImage(x.path, isLogo ? 'logo' : 'signature');
      if (saved == null) {
        if (mounted) showSnack(context, 'Could not save the image', error: true);
        return;
      }
      final sp = await SharedPreferences.getInstance();
      if (isLogo) {
        _logoPath = saved;
        await sp.setString('business_logo_path', saved);
      } else {
        _signPath = saved;
        await sp.setString('business_signature_path', saved);
      }
      if (mounted) {
        setState(() {});
        showSnack(context, isLogo ? 'Logo saved' : 'Signature saved');
      }
    } catch (_) {
      if (mounted) showSnack(context, 'Could not open the gallery', error: true);
    }
  }

  Future<void> _save() async {
    final shop = _shopC.text.trim();
    final owner = _ownerC.text.trim();
    final mobile = _mobileC.text.trim();
    if (shop.isEmpty) {
      showSnack(context, 'Shop name cannot be empty', error: true);
      return;
    }
    if (mobile.isNotEmpty && mobile.length != 10) {
      showSnack(context, 'Mobile number must be 10 digits', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      // Cloud: users/{uid} profile fields (rules: owner may edit ONLY these).
      await AccessService.instance.updateBusinessProfile(
        businessName: shop,
        ownerName: owner,
        mobile: mobile,
        city: _cityC.text.trim(),
        address: _addrC.text.trim(),
        gst: _gstC.text.trim(),
      );
      // Local: the shop name prints on the PDF bill.
      try {
        await Repo.instance.setMeta('shop_name', shop);
      } catch (_) {}
      if (!mounted) return;
      showSnack(context, 'Business profile saved');
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        showSnack(context, 'Saved locally - cloud update failed (offline?)',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const RubyAppBar(title: 'Business Profile', subtitle: 'Shop details & branding'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Ruby.ruby))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _readOnlyEmail(),
                const SizedBox(height: 16),
                const SectionHeader('Shop details', color: Ruby.ruby),
                const SizedBox(height: 6),
                _field(_shopC, 'Shop / Business name', FontWeight.w600),
                const SizedBox(height: 12),
                _field(_ownerC, 'Owner name'),
                const SizedBox(height: 12),
                _field(_mobileC, 'Mobile number (10 digits)',
                    type: TextInputType.phone, digits: true),
                const SizedBox(height: 12),
                _field(_cityC, 'City'),
                const SizedBox(height: 12),
                _field(_addrC, 'Shop address'),
                const SizedBox(height: 12),
                _field(_gstC, 'GST number (optional)', upper: true),
                const SizedBox(height: 20),
                const SectionHeader('Branding', color: Ruby.ruby),
                const SizedBox(height: 6),
                _imageRow(
                  label: 'Business Logo',
                  path: _logoPath,
                  onTap: () => _pickImage(isLogo: true),
                ),
                const SizedBox(height: 10),
                _imageRow(
                  label: 'Signature',
                  path: _signPath,
                  onTap: () => _pickImage(isLogo: false),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('SAVE',
                          style: TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 12),
                const Text(
                  'These details sync to your account, so both of your '
                  'devices show the same business profile.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, height: 1.45, color: Ruby.faint),
                ),
              ],
            ),
    );
  }

  Widget _readOnlyEmail() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Ruby.fieldBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Ruby.line),
      ),
      child: Row(
        children: [
          const Icon(Icons.alternate_email, size: 18, color: Ruby.ruby),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _email.isEmpty ? 'Google account' : _email,
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600, color: Ruby.ink),
            ),
          ),
          const Text('read-only', style: TextStyle(fontSize: 10.5, color: Ruby.faint)),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String hint, {
    FontWeight weight = FontWeight.normal,
    TextInputType type = TextInputType.text,
    bool digits = false,
    bool upper = false,
  }) {
    return TextField(
      controller: c,
      keyboardType: type,
      textCapitalization: upper ? TextCapitalization.characters : TextCapitalization.words,
      inputFormatters: digits
          ? [LengthLimitingTextInputFormatter(10)]
          : null,
      decoration: InputDecoration(hintText: hint, isDense: false),
      style: TextStyle(fontSize: 15, fontWeight: weight),
    );
  }

  Widget _imageRow({
    required String label,
    required String path,
    required VoidCallback onTap,
  }) {
    final file = path.isEmpty ? null : File(path);
    final exists = file != null && file.existsSync();
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Ruby.line),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Ruby.fieldBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Ruby.line),
              ),
              child: exists
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.file(file!, fit: BoxFit.cover),
                    )
                  : const Icon(Icons.image_outlined, color: Ruby.faint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Ruby.ink)),
                  const SizedBox(height: 2),
                  Text(exists ? 'Tap to change (from gallery)' : 'Tap to add from gallery',
                      style: const TextStyle(fontSize: 12, color: Ruby.muted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Ruby.faint),
          ],
        ),
      ),
    );
  }
}
