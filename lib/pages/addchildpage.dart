import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:docapp/api/api_constant.dart';
import 'package:docapp/model/customer.dart' as model;
import 'package:docapp/storage/Token_storage.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AddChildPage extends StatefulWidget {
  final model.Customer parent;

  const AddChildPage({super.key, required this.parent});

  @override
  State<AddChildPage> createState() => _AddChildPageState();
}

class _AddChildPageState extends State<AddChildPage> {
  static const Color kPrimaryBlue = Color(0xFF38B6E4);
  static const double kScreenPadding = 18;
  static const int kMaxImageDimension = 1024;
  static const int kPngLevel = 6;

  static String get _apiBaseUrl => ApiConstants.baseUrl;
  String get _apiBaseNormalized {
    var b = _apiBaseUrl.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    if (!b.toLowerCase().endsWith('/api')) b = '$b/api';
    return b;
  }

  final ImagePicker _picker = ImagePicker();
  File? _imageFile;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _surnameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();

  DateTime? _selectedDate;
  String? _gender;
  List<Map<String, String>> _customEntries = [];

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadCustomEntries();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  // ---------- helpers ----------

  int? _parentId() {
    final sid = widget.parent.serverId;
    if (sid != null && sid.isNotEmpty) {
      final v = int.tryParse(sid);
      if (v != null) return v;
    }
    try {
      final m = widget.parent.toMap();
      final v = m['id'] ?? m['Id'] ?? m['CustomerDataId'] ?? m['CustomerId'];
      if (v is int) return v;
      if (v is String) return int.tryParse(v);
    } catch (_) {}
    return null;
  }

  Future<void> _loadCustomEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('custom_entries');
    if (jsonString != null) {
      final List<dynamic> list = json.decode(jsonString);
      setState(() {
        _customEntries = list.map((e) => Map<String, String>.from(e)).toList();
      });
    }
  }

  Future<void> _saveCustomEntries() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_entries', json.encode(_customEntries));
  }

  String _othersFromEntries() {
    if (_customEntries.isEmpty) return "";
    return _customEntries
        .where((e) => (e['type']?.trim().isNotEmpty ?? false) || (e['detail']?.trim().isNotEmpty ?? false))
        .map((e) {
          final t = (e['type'] ?? '').trim();
          final d = (e['detail'] ?? '').trim();
          if (t.isNotEmpty && d.isNotEmpty) return "$t: $d";
          return t.isNotEmpty ? t : d;
        })
        .where((s) => s.isNotEmpty)
        .join(" | ");
  }

  // dd/MM/yyyy -> ISO8601 UTC with Z
  String _dobIso8601Z() {
    if (_selectedDate == null) return DateTime.now().toUtc().toIso8601String();
    final d = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
    return d.toUtc().toIso8601String();
  }

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) setState(() => _imageFile = File(pickedFile.path));
  }

  Future<Uint8List?> _compressToPng(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      img.Image processed = decoded;
      final w = decoded.width;
      final h = decoded.height;
      if (w > kMaxImageDimension || h > kMaxImageDimension) {
        final scale = (w > h) ? kMaxImageDimension / w : kMaxImageDimension / h;
        final newW = (w * scale).round();
        final newH = (h * scale).round();
        processed = img.copyResize(decoded, width: newW, height: newH, interpolation: img.Interpolation.cubic);
      }
      final png = img.encodePng(processed, level: kPngLevel);
      return Uint8List.fromList(png);
    } catch (_) {
      return null;
    }
  }

  InputDecoration _inputDecoration(String placeholder, {IconData? icon}) {
    return InputDecoration(
      hintText: placeholder,
      hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 16),
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 14),
      border: InputBorder.none,
      prefixIcon: icon != null ? Icon(icon, color: Colors.black54, size: 20) : null,
    );
  }

  String _digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');
  Set<String> _phoneKeysForMatch(String s) {
    final d = _digitsOnly(s);
    final set = <String>{};
    if (d.isEmpty) return set;
    set.add(d);
    if (d.length >= 10) set.add(d.substring(d.length - 10));
    return set;
  }

  Future<bool> _isDuplicatePhoneLocal(String rawPhone) async {
    final keysToCheck = _phoneKeysForMatch(rawPhone);
    if (keysToCheck.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('customers');
    if (existing == null) return false;

    try {
      final List<dynamic> list = json.decode(existing);
      for (final item in list) {
        if (item is Map) {
          final m = Map<String, dynamic>.from(item);
          final candidates = [
            m['phone'], m['Phone'], m['phoneNumber'], m['PhoneNumber'],
          ].whereType<String>();
          for (final ph in candidates) {
            final ks = _phoneKeysForMatch(ph);
            for (final k in ks) {
              if (keysToCheck.contains(k)) return true;
            }
          }
          if (m['family'] is List) {
            for (final f in (m['family'] as List)) {
              if (f is Map) {
                final ph = f['phone']?.toString() ?? f['PhoneNumber']?.toString();
                if (ph != null) {
                  final ks = _phoneKeysForMatch(ph);
                  for (final k in ks) {
                    if (keysToCheck.contains(k)) return true;
                  }
                }
              }
            }
          }
        }
      }
    } catch (_) {}
    return false;
  }

  Map<String, dynamic> _unwrapApiPayload(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      final r = raw['Response'];
      if (r is Map<String, dynamic>) return r;
      if (r is List && r.isNotEmpty && r.first is Map<String, dynamic>) {
        return Map<String, dynamic>.from(r.first as Map);
      }
      return raw;
    }
    if (raw is List && raw.isNotEmpty && raw.first is Map<String, dynamic>) {
      return Map<String, dynamic>.from(raw.first as Map);
    }
    return {};
  }

  Future<void> _persistServerParentWithChildren(Map<String, dynamic> parentResp) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('customers');
    final List<dynamic> customers = data != null && data.isNotEmpty ? json.decode(data) : [];

    final serverChildDatas = (parentResp['ChildDatas'] is List) ? List.from(parentResp['ChildDatas'] as List) : <dynamic>[];
    final familyList = <Map<String, dynamic>>[];
    for (final c in serverChildDatas) {
      if (c is Map) {
        final cm = Map<String, dynamic>.from(c);
        familyList.add({
          'name': cm['Name']?.toString() ?? '',
          'surname': cm['Surname']?.toString() ?? '',
          'phone': cm['PhoneNumber']?.toString() ?? '',
          'email': cm['EmailId']?.toString() ?? '',
          'address': cm['Address']?.toString() ?? '',
          'dob': '',
          'gender': (cm['Gender']?.toString() ?? '').toLowerCase(),
          'serverId': cm['Id']?.toString(),
          'fileId': cm['FileId'],
          'customEntries': <Map<String, String>>[],
        });
      }
    }

    final parentServerId = parentResp['Id']?.toString();
    int index = -1;
    for (int i = 0; i < customers.length; i++) {
      final m = Map<String, dynamic>.from(customers[i] as Map);
      final sidStr = (m['serverId'] ?? m['Id'] ?? m['id'] ?? m['CustomerDataId'])?.toString();
      if (sidStr != null && parentServerId != null && sidStr == parentServerId) { index = i; break; }
      final phone = m['phone']?.toString() ?? m['PhoneNumber']?.toString();
      if (phone != null && phone == (parentResp['PhoneNumber']?.toString() ?? '')) { index = i; break; }
    }

    final parentLocal = <String, dynamic>{
      'serverId': parentServerId,
      'ChildDatas': serverChildDatas, // exact server structure saved
      'Documents': parentResp['Documents'] ?? [],
      'family': familyList, // offline UI mirror
    };

    if (index != -1) {
      final existing = Map<String, dynamic>.from(customers[index] as Map);
      customers[index] = {...existing, ...parentLocal};
    } else {
      customers.add({...widget.parent.toMap(), ...parentLocal});
    }

    await prefs.setString('customers', json.encode(customers));
  }

  Map<String, dynamic>? _pickNewChildFromResponse(Map<String, dynamic> parentResp, int parentId) {
    final childs = parentResp['ChildDatas'];
    if (childs is List && childs.isNotEmpty) {
      for (final c in childs) {
        if (c is Map) {
          final pid = int.tryParse((c['ParentCustomerDataId'] ?? '').toString()) ?? c['ParentCustomerDataId'] as int?;
          if (pid == parentId) return Map<String, dynamic>.from(c);
        }
      }
      return Map<String, dynamic>.from(childs.last as Map);
    }
    return null;
  }

  // ---------- submit (child inside ChildDatas) ----------

  Future<void> _submit() async {
    final parentId = _parentId();
    if (parentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Missing parent Id. Open this page from a valid parent.")),
      );
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Name is required")));
      return;
    }
    if (_phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Phone No is required")));
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);

    try {
      final phoneRaw = _phoneController.text.trim();
      if (await _isDuplicatePhoneLocal(phoneRaw)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("This mobile number already exists locally. Please use a different number.")),
        );
        return;
      }

      Uint8List? pngBytes;
      String fileName = "Profile_Image.png";
      if (_imageFile != null) {
        pngBytes = await _compressToPng(_imageFile!);
        final base = _imageFile!.path.split(Platform.pathSeparator).last;
        if (base.isNotEmpty) fileName = base;
      }

      final token = await TokenStorage.getToken();
      final headers = <String, String>{
        "Content-Type": "application/json; charset=utf-8",
        "Accept": "application/json",
        if (token != null && token.isNotEmpty) "Authorization": "Bearer $token",
      };

      final dobIso = _dobIso8601Z();
      final httpFileData = (pngBytes != null)
          ? {
              "Id": 0,
              "IsModified": true,
              "FileData": base64Encode(pngBytes),
              "FileName": fileName,
              "FileType": "image/png",
              "Remarks": "Profile Photo",
              "IsDeleted": false,
              "CustomerDataId": 0,
            }
          : null;

      final childPayload = {
        "Id": 0,
        "ParentCustomerDataId": parentId, // link to parent
        "Name": _nameController.text.trim(),
        "Surname": _surnameController.text.trim(),
        "PhoneNumber": phoneRaw,
        "FileId": 0,
        "EmailId": _emailController.text.trim(),
        "Address": _addressController.text.trim(),
        "Gender": (_gender ?? "").toLowerCase(),
        "Others": _othersFromEntries(),
        "DOB": dobIso,
        "SDOB": dobIso,
        "HttpFileData": httpFileData,
        "ChildDatas": [],
        "Documents": [],
      };

      final payload = <String, dynamic>{
        "Id": parentId,
        "ParentCustomerDataId": parentId,
        "ChildDatas": [childPayload],
        "Documents": [],
      };

      final url = '$_apiBaseNormalized/CustomerDataM/AddAsync';
      final res = await http.post(Uri.parse(url), headers: headers, body: jsonEncode(payload));
      if (!(res.statusCode >= 200 && res.statusCode < 300)) {
        final msg = _extractServerError(res.body) ?? 'Server error ${res.statusCode}';
        throw Exception(msg);
      }

      final decoded = res.body.trim().isEmpty ? {} : jsonDecode(res.body);
      final parentResp = _unwrapApiPayload(decoded);

      await _persistServerParentWithChildren(parentResp);

      final childMap = _pickNewChildFromResponse(parentResp, parentId) ?? {};
      final childCustomer = model.Customer(
        name: childMap['Name']?.toString() ?? _nameController.text.trim(),
        surname: childMap['Surname']?.toString() ?? _surnameController.text.trim(),
        phone: childMap['PhoneNumber']?.toString() ?? phoneRaw,
        email: childMap['EmailId']?.toString() ?? _emailController.text.trim(),
        address: childMap['Address']?.toString() ?? _addressController.text.trim(),
        dob: _dobController.text.trim(),
        gender: (childMap['Gender']?.toString() ?? (_gender ?? "")).toLowerCase(),
        customEntries: _customEntries,
        photo: null,
        imageBytes: pngBytes,
        serverId: childMap['Id']?.toString(),
        fileId: (childMap['FileId'] is int)
            ? childMap['FileId'] as int
            : int.tryParse(childMap['FileId']?.toString() ?? ''),
      );

      if (!mounted) return;
      Navigator.pop<model.Customer>(context, childCustomer);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Submit failed: $e")));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _extractServerError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        if (decoded['message'] is String) return decoded['message'] as String;
        if (decoded['error'] is String) return decoded['error'] as String;
        if (decoded['errors'] is Map) {
          final errors = decoded['errors'] as Map;
          final lines = <String>[];
          for (final entry in errors.entries) {
            final key = entry.key;
            final val = entry.value;
            if (val is List && val.isNotEmpty) {
              lines.add("$key: ${val.join(', ')}");
            } else if (val is String) lines.add("$key: $val");
          }
          if (lines.isNotEmpty) return lines.join('\n');
        }
      }
    } catch (_) {}
    return null;
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 60,
            pinned: true,
            backgroundColor: Colors.transparent,
            leading: const BackButton(color: Colors.white),
            title: const Text(
              "Add Family Member",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(image: AssetImage("assets/images/Background2.jpeg"), fit: BoxFit.cover),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: kScreenPadding),
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset("assets/images/logo2.png", height: 40, width: 60),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.family_restroom, color: Colors.blue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Under: ${widget.parent.name} ${widget.parent.surname}".trim(),
                              style: const TextStyle(color: Colors.blue),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                    Center(
                      child: GestureDetector(
                        onTap: _pickImage,
                        child: CircleAvatar(
                          radius: 60,
                          backgroundColor: Colors.grey.shade200,
                          backgroundImage: _imageFile != null ? FileImage(_imageFile!) : null,
                          child: _imageFile == null ? const Icon(Icons.person, size: 40, color: Colors.grey) : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),

                    TextField(controller: _nameController, decoration: _inputDecoration("Name")),
                    const Divider(color: Colors.black12),
                    TextField(controller: _surnameController, decoration: _inputDecoration("Surname")),
                    const Divider(color: Colors.black12),
                    TextField(
                      controller: _dobController,
                      readOnly: true,
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate ?? DateTime(2000),
                          firstDate: DateTime(1900),
                          lastDate: now,
                        );
                        if (picked != null) {
                          setState(() {
                            _selectedDate = picked;
                            _dobController.text = "${picked.day}/${picked.month}/${picked.year}";
                          });
                        }
                      },
                      decoration: _inputDecoration("Date of Birth").copyWith(
                        suffixIcon: const Icon(Icons.keyboard_arrow_down, color: Colors.black54),
                      ),
                    ),
                    const Divider(color: Colors.black12),
                    TextField(controller: _emailController, decoration: _inputDecoration("Email")),
                    const Divider(color: Colors.black12),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: _inputDecoration("Phone No"),
                    ),
                    const Divider(color: Colors.black12),
                    TextField(controller: _addressController, decoration: _inputDecoration("Address")),
                    const Divider(color: Colors.black12),

                    const SizedBox(height: 20),
                    const Align(alignment: Alignment.centerLeft, child: Text("Gender", style: TextStyle(color: Colors.grey))),
                    Row(
                      children: ["Male", "Female", "Other"].map((g) {
                        return Expanded(
                          child: Row(
                            children: [
                              Radio<String>(
                                value: g,
                                groupValue: _gender,
                                onChanged: (val) => setState(() => _gender = val),
                                activeColor: Colors.black87,
                              ),
                              Text(g),
                            ],
                          ),
                        );
                      }).toList(),
                    ),

                    const Divider(color: Colors.black12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final typeController = TextEditingController();
                          final detailController = TextEditingController();

                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text("Add Custom Entry"),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(controller: typeController, decoration: const InputDecoration(labelText: "Type")),
                                  TextField(controller: detailController, decoration: const InputDecoration(labelText: "Detail")),
                                ],
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                                ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Add")),
                              ],
                            ),
                          );
                          if (ok == true) {
                            setState(() {
                              _customEntries.add({
                                "type": typeController.text.trim(),
                                "detail": detailController.text.trim(),
                              });
                            });
                            await _saveCustomEntries();
                          }
                        },
                        icon: Icon(Icons.add, color: kPrimaryBlue),
                        label: Text("Add Custom Entry", style: TextStyle(color: kPrimaryBlue)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          elevation: 0,
                          side: const BorderSide(color: kPrimaryBlue),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (_customEntries.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: _customEntries.map((entry) {
                            return Chip(
                              label: Text("${entry['type']}: ${entry['detail']}"),
                              backgroundColor: Colors.grey.shade200,
                              deleteIcon: const Icon(Icons.close, size: 18),
                              onDeleted: () async {
                                setState(() => _customEntries.remove(entry));
                                await _saveCustomEntries();
                              },
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(kScreenPadding),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            image: const DecorationImage(image: AssetImage("assets/images/Background2.jpeg"), fit: BoxFit.cover),
          ),
          child: ElevatedButton(
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _submitting
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                        SizedBox(width: 10),
                        Text("Submitting...", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      ],
                    )
                  : const Text("Submit", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }
}