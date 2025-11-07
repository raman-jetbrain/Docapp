import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:docapp/api/api_constant.dart';
import 'package:docapp/model/customer.dart' as model;
import 'package:docapp/storage/Token_storage.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

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
          } else if (val is String) {
            lines.add("$key: $val");
          }
        }
        if (lines.isNotEmpty) return lines.join('\n');
      }
    }
  } catch (_) {}
  return null;
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v.toString());
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

class AddNewUserPage extends StatefulWidget {
  final int? parentServerId;
  final String? parentDisplay;

  const AddNewUserPage({super.key, this.parentServerId, this.parentDisplay});

  @override
  State<AddNewUserPage> createState() => _AddNewUserPageState();
}

class _AddNewUserPageState extends State<AddNewUserPage> {
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

  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _surnameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _registeredDobController = TextEditingController();

  // Marital Status + Marriage Date
  final TextEditingController _marriageDateController = TextEditingController();
  DateTime? _selectedMarriageDate;
  String? _maritalStatus; // "Single", "Married", "others"

  DateTime? _selectedDate; // DOB
  DateTime? _selectedRegisteredDate; // Registered DOB (SDOB)
  String? _gender;
  List<Map<String, String>> _customEntries = [];

  bool _isSubmitting = false;
  int? _parentServerId;

  bool get _isAddingChild => _parentServerId != null;

  @override
  void initState() {
    super.initState();
    _parentServerId = widget.parentServerId;
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
    _registeredDobController.dispose();
    _marriageDateController.dispose();
    super.dispose();
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

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) setState(() => _imageFile = File(pickedFile.path));
  }

  // Pick DOB
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dobController.text = "${picked.day}/${picked.month}/${picked.year}";
      });
    }
  }

  // Pick Registered DOB (SDOB)
  Future<void> _rpickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedRegisteredDate ?? now,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _selectedRegisteredDate = picked;
        _registeredDobController.text = "${picked.day}/${picked.month}/${picked.year}";
      });
    }
  }

  // Pick Marriage Date
  Future<void> _pickMarriageDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMarriageDate ?? now,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _selectedMarriageDate = picked;
        _marriageDateController.text = "${picked.day}/${picked.month}/${picked.year}";
      });
    }
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey, fontSize: 16),
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 14),
      border: InputBorder.none,
    );
  }

  Future<void> _showAddCustomEntryDialog() async {
    final typeController = TextEditingController();
    final detailController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add Custom Entry"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: typeController,
              decoration: const InputDecoration(labelText: "Type"),
            ),
            TextField(
              controller: detailController,
              decoration: const InputDecoration(labelText: "Detail"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Add"),
          ),
        ],
      ),
    );

    if (result == true) {
      setState(() {
        _customEntries.add({
          "type": typeController.text.trim(),
          "detail": detailController.text.trim(),
        });
      });
      await _saveCustomEntries();
    }
  }

  String? _dobIso8601Z() {
    if (_selectedDate == null) return null;
    final dt = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
    );
    return dt.toUtc().toIso8601String();
  }

  // Registered DOB -> ISO8601 (UTC)
  String? _registeredDobIso8601Z() {
    if (_selectedRegisteredDate == null) return null;
    final dt = DateTime(
      _selectedRegisteredDate!.year,
      _selectedRegisteredDate!.month,
      _selectedRegisteredDate!.day,
    );
    return dt.toUtc().toIso8601String();
  }

  // Married Date -> ISO8601 (UTC)
  String? _marriedDateIso8601Z() {
    if (_selectedMarriageDate == null) return null;
    final dt = DateTime(
      _selectedMarriageDate!.year,
      _selectedMarriageDate!.month,
      _selectedMarriageDate!.day,
    );
    return dt.toUtc().toIso8601String();
  }

  // Build Others string (kept for display/local use)
  String _othersAsString() {
    final parts = <String>[];

    final ms = _maritalStatus?.trim();
    if (ms != null && ms.isNotEmpty) {
      parts.add("Marital Status: $ms");
      if (ms == 'Married') {
        final md = _marriageDateController.text.trim();
        if (md.isNotEmpty) parts.add("Marriage Date: $md");
      }
    }

    if (_customEntries.isNotEmpty) {
      final custom = _customEntries
          .where(
            (e) =>
                (e['type']?.trim().isNotEmpty ?? false) ||
                (e['detail']?.trim().isNotEmpty ?? false),
          )
          .map((e) {
            final t = (e['type'] ?? '').trim();
            final d = (e['detail'] ?? '').trim();
            if (t.isNotEmpty && d.isNotEmpty) return "$t: $d";
            return t.isNotEmpty ? t : d;
          })
          .where((s) => s.isNotEmpty)
          .toList();
      parts.addAll(custom);
    }

    return parts.join(" | ");
  }

  // Convert to PNG
  Future<Uint8List?> _compressToPng(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      img.Image processed = decoded;
      final w = decoded.width;
      final h = decoded.height;
      const maxDim = kMaxImageDimension;
      if (w > maxDim || h > maxDim) {
        final scale = (w > h) ? maxDim / w : maxDim / h;
        final newW = (w * scale).round();
        final newH = (h * scale).round();
        processed = img.copyResize(
          decoded,
          width: newW,
          height: newH,
          interpolation: img.Interpolation.cubic,
        );
      }

      final png = img.encodePng(processed, level: kPngLevel);
      return Uint8List.fromList(png);
    } catch (e) {
      debugPrint('[PNG] Compression failed: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _buildHttpFileData() async {
    if (_imageFile == null) return null;
    try {
      final pngBytes = await _compressToPng(_imageFile!);
      if (pngBytes == null || pngBytes.isEmpty) return null;
      final b64 = base64Encode(pngBytes);

      final path = _imageFile!.path;
      final fileNameOnly = path.split(Platform.pathSeparator).last;
      final dot = fileNameOnly.lastIndexOf('.');
      final baseName = dot > 0 ? fileNameOnly.substring(0, dot) : fileNameOnly;

      return {
        "IsModified": true,
        "FileData": b64,
        "FileName": "$baseName.png",
        "FileType": "image/png",
        "Remarks": "",
        "IsDeleted": false,
      };
    } catch (e) {
      debugPrint('[PNG] Build HttpFileData error: $e');
      return null;
    }
  }

  // ===== Unique counters (previous + 1) =====
  Future<int> _takeNextCustomerId() async {
    final prefs = await SharedPreferences.getInstance();
    int current = prefs.getInt('next_server_customer_id') ?? 0;
    if (current == 0) {
      int maxId = 0;
      final existing = prefs.getString('customers');
      if (existing != null) {
        try {
          final List<dynamic> list = json.decode(existing);
          for (final item in list) {
            if (item is Map) {
              final m = Map<String, dynamic>.from(item);
              for (final key in ['serverId', 'id', 'Id']) {
                final v = _toInt(m[key]);
                if (v != null && v > maxId) maxId = v;
              }
            }
          }
        } catch (_) {}
      }
      current = maxId;
    }
    final next = current + 1;
    await prefs.setInt('next_server_customer_id', next);
    return next;
  }

  Future<int> _takeNextFileId() async {
    final prefs = await SharedPreferences.getInstance();
    int current = prefs.getInt('next_server_file_id') ?? 0;
    if (current == 0) {
      int maxId = 0;
      final existing = prefs.getString('customers');
      if (existing != null) {
        try {
          final List<dynamic> list = json.decode(existing);
          for (final item in list) {
            if (item is Map) {
              final m = Map<String, dynamic>.from(item);
              final v = _toInt(m['fileId']);
              if (v != null && v > maxId) maxId = v;
              if (m['HttpFileData'] is Map) {
                final fid = _toInt((m['HttpFileData'] as Map)['Id']);
                if (fid != null && fid > maxId) maxId = fid;
              }
            }
          }
        } catch (_) {}
      }
      current = maxId;
    }
    final next = current + 1;
    await prefs.setInt('next_server_file_id', next);
    return next;
  }

  Future<void> _ensureCounterAtLeast(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    final curr = prefs.getInt(key) ?? 0;
    if (curr < value) await prefs.setInt(key, value);
  }

  // ---- POST call with payload matching your schema ----
  Future<Map<String, dynamic>> _createCustomerOnServerExactPayload({
    required String name,
    required String surname,
    required String phoneNumber,
    required String emailId,
    required String address,
    required String gender,
    required String others,
    required String? dobIsoZ,
    required String? sDobIsoZ, // Registered DOB
    required int id,
    int? parentCustomerDataId,
    int? fileId,
    Map<String, dynamic>? httpFileData,

    // NEW: fields to match server schema
    required String? martialStatus,   // "Single" | "Married" | "others"
    required String? marriedDateIsoZ, // ISO8601Z when married
    List<Map<String, dynamic>>? childDatas,
    List<Map<String, dynamic>>? documents,
  }) async {
    final token = await TokenStorage.getToken();
    final hasImage =
        (httpFileData != null) &&
        (((httpFileData['FileData'] as String?) ?? '').isNotEmpty);

    final httpFilePayload = hasImage
        ? {
            "Id": fileId ?? 0,
            "IsModified": true,
            "FileData": httpFileData["FileData"] ?? "",
            "FileName": (httpFileData["FileName"] ?? "Profile_Image.png").toString(),
            "FileType": (httpFileData["FileType"] ?? "image/png").toString(),
            "Remarks": (httpFileData["Remarks"] ?? "").toString(),
            "IsDeleted": false,
            "CustomerDataId": id,
          }
        : null;

    final nowUtcIso = DateTime.now().toUtc().toIso8601String();

    final payload = <String, dynamic>{
      "Id": id,
      "ParentCustomerDataId": parentCustomerDataId ?? 0,
      "Name": name,
      "Surname": surname,
      "PhoneNumber": phoneNumber,
      "FileId": hasImage ? (fileId ?? 0) : 0,
      "EmailId": emailId,
      "Address": address,
      "Gender": gender.toLowerCase(),
      "Others": others,
      "DOB": dobIsoZ ?? nowUtcIso,
      "SDOB": sDobIsoZ ?? dobIsoZ ?? nowUtcIso,
      "MartialStatus": martialStatus ?? "",
      "MarriedDate": (martialStatus != null && martialStatus.toLowerCase() == 'married')
          ? (marriedDateIsoZ ?? nowUtcIso)
          : null,
      "HttpFileData": httpFilePayload,
      "ChildDatas": childDatas ?? <Map<String, dynamic>>[],
      "Documents": documents ?? <Map<String, dynamic>>[],
    };

    debugPrint('[Add] Using customerId=$id, parentId=${parentCustomerDataId ?? 0}, fileId=${hasImage ? fileId : 0}');

    final headers = <String, String>{
      "Content-Type": "application/json; charset=utf-8",
      "Accept": "application/json",
      if (token != null && token.isNotEmpty) "Authorization": "Bearer $token",
    };

    final url = '$_apiBaseNormalized/CustomerDataM/AddAsync';
    try {
      // Safe-logging without exposing base64
      final safePayload = Map<String, dynamic>.from(payload);
      if (safePayload['HttpFileData'] is Map) {
        final fd = Map<String, dynamic>.from(safePayload['HttpFileData'] as Map);
        final b64 = (fd['FileData'] as String?);
        fd['FileData'] = b64 == null ? "" : "<base64:${(b64.length / 1024).toStringAsFixed(1)}KB>";
        safePayload['HttpFileData'] = fd;
      }
      debugPrint('[Add] POST $url');
      debugPrint('[Add] Payload (safe): ${jsonEncode(safePayload)}');
      debugPrint('[Add] Headers: ${jsonEncode(headers)}');

      final res = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(payload),
      );

      debugPrint('[Add] <- ${res.statusCode}');
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (res.body.trim().isEmpty) return {};
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is List &&
            decoded.isNotEmpty &&
            decoded.first is Map<String, dynamic>) {
          return decoded.first as Map<String, dynamic>;
        }
        return {};
      }
      final msg = _extractServerError(res.body) ?? 'Server error ${res.statusCode}';
      throw Exception(msg);
    } catch (e) {
      debugPrint('[Add] POST failed: $e');
      rethrow;
    }
  }

  // Local-only id for cache (not for images)
  Future<int> _peekNextLocalCustomerId() async {
    final prefs = await SharedPreferences.getInstance();
    int? nextId = prefs.getInt('next_local_customer_id');
    if (nextId != null && nextId > 0) return nextId;

    int maxId = 0;
    final existing = prefs.getString('customers');
    if (existing != null) {
      try {
        final List<dynamic> list = json.decode(existing);
        for (final item in list) {
          if (item is Map) {
            final local = _toInt(item['localId']);
            if (local != null && local > maxId) maxId = local;
          }
        }
      } catch (_) {}
    }

    nextId = maxId + 1;
    await prefs.setInt('next_local_customer_id', nextId);
    return nextId;
  }

  Future<void> _advanceNextLocalCustomerId(int justUsed) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt('next_local_customer_id') ?? 1;
    final next = (justUsed + 1) > current ? (justUsed + 1) : current;
    await prefs.setInt('next_local_customer_id', next);
  }

  // ====== Duplicate phone checking ======
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
            m['phone'],
            m['Phone'],
            m['phoneNumber'],
            m['PhoneNumber'],
          ].whereType<String>();
          for (final ph in candidates) {
            final ks = _phoneKeysForMatch(ph);
            for (final k in ks) {
              if (keysToCheck.contains(k)) return true;
            }
          }
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Name is required")));
      return;
    }
    if (_phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Phone No is required")));
      return;
    }
    // If Married, require Marriage Date
    if ((_maritalStatus ?? '').toLowerCase() == 'married' &&
        _marriageDateController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select marriage date.")),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    try {
      final phoneRaw = _phoneController.text.trim();

      // Quick local duplicate check
      if (await _isDuplicatePhoneLocal(phoneRaw)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("This mobile number already exists locally. Please use a different number."),
          ),
        );
        return;
      }

      // Generate ids
      final localId = await _peekNextLocalCustomerId();
      final generatedCustomerId = await _takeNextCustomerId();

      final httpFileData = await _buildHttpFileData();
      final hasImage = httpFileData != null && (((httpFileData['FileData'] as String?) ?? '').isNotEmpty);
      final generatedFileId = hasImage ? await _takeNextFileId() : null;

      final dobIsoZ = _dobIso8601Z();
      final sDobIsoZ = _registeredDobIso8601Z();
      final marriedDateIsoZ = _marriedDateIso8601Z();
      final others = _othersAsString();

      // Send to API with exact schema
      final serverResponse = await _createCustomerOnServerExactPayload(
        id: generatedCustomerId,
        parentCustomerDataId: _parentServerId,
        name: _nameController.text.trim(),
        surname: _surnameController.text.trim(),
        phoneNumber: phoneRaw,
        emailId: _emailController.text.trim(),
        address: _addressController.text.trim(),
        gender: _gender?.trim() ?? "",
        others: others,
        dobIsoZ: dobIsoZ,
        sDobIsoZ: sDobIsoZ,
        fileId: generatedFileId,
        httpFileData: httpFileData != null ? {...httpFileData, "FileType": "image/png"} : null,

        // NEW fields
        martialStatus: _maritalStatus,
        marriedDateIsoZ: (_maritalStatus?.toLowerCase() == 'married') ? marriedDateIsoZ : null,
        documents: const [], // attach documents here if you have any
        childDatas: const [], // attach children here if you are sending nested
      );

      final created = _unwrapApiPayload(serverResponse);
      final serverId =
          _toInt(created['Id'] ?? created['CustomerDataMId'] ?? created['CustomerId'] ?? created['CustomerDataId']) ??
          generatedCustomerId;

      final fileId =
          _toInt(
            created['FileId'] ??
                (created['HttpFileData'] is Map
                    ? (created['HttpFileData']['Id'] ?? created['HttpFileData']['FileId'])
                    : null),
          ) ??
          (hasImage ? generatedFileId : null);

      await _ensureCounterAtLeast('next_server_customer_id', serverId);
      if (fileId != null) {
        await _ensureCounterAtLeast('next_server_file_id', fileId);
      }

      // For immediate UI only
      Uint8List? immediateBytes;
      final fdStr = (httpFileData?['FileData'] as String?);
      if (fdStr != null && fdStr.isNotEmpty) {
        try {
          immediateBytes = base64Decode(fdStr);
        } catch (_) {}
      }

      // Persist only lightweight info (no image in local storage)
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString('customers');
      final List<dynamic> list = existing != null ? json.decode(existing) : [];

      final newCustomerMap = {
        "localId": localId,
        "name": _nameController.text.trim(),
        "surname": _surnameController.text.trim(),
        "phone": phoneRaw,
        "address": _addressController.text.trim(),
        "email": _emailController.text.trim(),
        "dob": _dobController.text.trim(),
        "registeredDob": _registeredDobController.text.trim(),
        "gender": (_gender ?? "").toLowerCase(),
        "customEntries": _customEntries,
        "serverId": serverId,
        "fileId": fileId,
        "parentServerId": _parentServerId,
        "maritalStatus": _maritalStatus,
        "marriageDate": _marriageDateController.text.trim(),
      };
      list.add(newCustomerMap);

      await prefs.setString('customers', json.encode(list));
      await prefs.setString('last_user', json.encode(newCustomerMap));
      await _advanceNextLocalCustomerId(localId);

      if (!mounted) return;

      // Return a Customer object (for FamilyPage)
      final customer = model.Customer(
        name: newCustomerMap['name'] as String,
        surname: newCustomerMap['surname'] as String,
        phone: newCustomerMap['phone'] as String,
        email: newCustomerMap['email'] as String,
        address: newCustomerMap['address'] as String,
        dob: newCustomerMap['dob'] as String,
        gender: newCustomerMap['gender'] as String,
        customEntries: (newCustomerMap['customEntries'] as List<dynamic>)
            .map<Map<String, String>>((e) => Map<String, String>.from(e))
            .toList(),
        photo: null,
        imageBytes: immediateBytes,
        serverId: serverId.toString(),
        fileId: fileId,
      );

      Navigator.pop<model.Customer>(context, customer);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Submit failed: $e")));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

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
              "Add New Customer",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            centerTitle: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage("assets/images/Background2.jpeg"),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: kScreenPadding),
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          "assets/images/logo2.png",
                          height: 40,
                          width: 60,
                        ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                child: Column(
                  children: [
                    if (_isAddingChild)
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
                            const Icon(Icons.group, color: Colors.blue),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Adding family member under: ${widget.parentDisplay ?? "#$_parentServerId"}",
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
                          backgroundImage: _imageFile != null
                              ? FileImage(_imageFile!)
                              : null,
                          child: _imageFile == null
                              ? const Icon(
                                  Icons.person,
                                  size: 40,
                                  color: Colors.grey,
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    TextField(
                      controller: _surnameController,
                      decoration: _inputDecoration("Surname"),
                    ),
                    const Divider(color: Colors.black12),
                    TextField(
                      controller: _nameController,
                      decoration: _inputDecoration("Name"),
                    ),
                    const Divider(color: Colors.black12),
                    TextField(
                      controller: _dobController,
                      readOnly: true,
                      onTap: _pickDate,
                      decoration: _inputDecoration("Date of Birth").copyWith(
                        suffixIcon: const Icon(
                          Icons.keyboard_arrow_down,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    const Divider(color: Colors.black12),
                    TextField(
                      controller: _registeredDobController,
                      readOnly: true,
                      onTap: _rpickDate,
                      decoration: _inputDecoration("Registered Date of Birth").copyWith(
                        suffixIcon: const Icon(
                          Icons.keyboard_arrow_down,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    const Divider(color: Colors.black12),
                    TextField(
                      controller: _emailController,
                      decoration: _inputDecoration("Email"),
                    ),
                    const Divider(color: Colors.black12),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: _inputDecoration("Phone No"),
                    ),
                    const Divider(color: Colors.black12),
                    TextField(
                      controller: _addressController,
                      decoration: _inputDecoration("Address"),
                    ),
                    const Divider(color: Colors.black12),
                    const SizedBox(height: 20),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Gender",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                    Row(
                      children: ["Male", "Female", "TransGender"].map((g) {
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

                    // Marital Status + conditional Marriage Date
                    const SizedBox(height: 12),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Marital Status",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                    Row(
                      children: ["Single", "Married", "others"].map((s) {
                        return Expanded(
                          child: Row(
                            children: [
                              Radio<String>(
                                value: s,
                                groupValue: _maritalStatus,
                                onChanged: (val) {
                                  setState(() {
                                    _maritalStatus = val;
                                    if (val != 'Married') {
                                      _selectedMarriageDate = null;
                                      _marriageDateController.clear();
                                    }
                                  });
                                },
                                activeColor: Colors.black87,
                              ),
                              Flexible(child: Text(s)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                    if (_maritalStatus == 'Married') ...[
                      TextField(
                        controller: _marriageDateController,
                        readOnly: true,
                        onTap: _pickMarriageDate,
                        decoration: _inputDecoration("Marriage Date").copyWith(
                          suffixIcon: const Icon(
                            Icons.calendar_today,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    ],
                    const Divider(color: Colors.black12),

                    ElevatedButton.icon(
                      onPressed: _showAddCustomEntryDialog,
                      icon: Icon(Icons.add, color: kPrimaryBlue),
                      label: Text(
                        "Add Custom Entry",
                        style: TextStyle(color: kPrimaryBlue),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        elevation: 0,
                        side: const BorderSide(color: kPrimaryBlue),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_customEntries.isNotEmpty)
                      Wrap(
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
            image: const DecorationImage(
              image: AssetImage("assets/images/Background2.jpeg"),
              fit: BoxFit.cover,
            ),
          ),
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _isSubmitting
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          "Submitting...",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    )
                  : const Text(
                      "Submit",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}