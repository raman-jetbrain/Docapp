import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:docapp/api/api_constant.dart';
import 'package:docapp/model/customer.dart';
import 'package:docapp/storage/Token_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class DescriptionPage extends StatefulWidget {
  final Customer customer;

  const DescriptionPage({super.key, required this.customer});

  @override
  State<DescriptionPage> createState() => _DescriptionPageState();
}

class _DescriptionPageState extends State<DescriptionPage> {
  static const Color kPrimaryBlue = Color(0xFF38B6E4);

  // Base URL normalization
  static String get _apiBaseUrl => ApiConstants.baseUrl;
  String get _apiBaseWithApi {
    var b = _apiBaseUrl.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    if (!b.toLowerCase().endsWith('/api')) b = '$b/api';
    return b;
  }

  late Customer _customer;

  // Editing state
  bool _isEditing = false;
  bool _isSubmitting = false;
  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _emailController = TextEditingController();
  final _dobController = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  File? _imageFile; // picked new file
  Uint8List? _existingImageBytes; // original bytes if available
  String? _gender; // Male / Female / Other
  DateTime? _selectedDate;
  List<Map<String, String>> _customEntries = [];

  int? _serverId; // server-side Id

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    _prefillFromCustomer(_customer);
    _resolveServerId(); // fetch serverId via API first, fallback to cache
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

  // Try API for Id, fallback to cache
  Future<void> _resolveServerId() async {
    await _loadServerIdFromApi();
    if (_serverId == null) {
      await _loadServerIdFromCache(_customer);
    }
  }

  // Normalize phone (digits only) to improve match reliability
  String _normalizePhone(String? v) {
    if (v == null) return '';
    return v.replaceAll(RegExp(r'\D+'), '');
  }

  // GET /api/CustomerDataM/GetAsync -> find this customer -> set _serverId
  Future<void> _loadServerIdFromApi() async {
    try {
      final token = await _resolveToken();
      if (token == null || token.isEmpty) {
        debugPrint('[Description] No token; cannot load serverId from API');
        return;
      }

      final url = '$_apiBaseWithApi/CustomerDataM/GetAsync';
      debugPrint('[Description] GET $url');

      final res = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint('[Description] <- ${res.statusCode}');

      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('[Description] GET failed: ${res.statusCode} ${res.body}');
        return;
      }

      final decoded = json.decode(res.body);
      final List<dynamic> list = decoded is Map && decoded['Response'] is List
          ? decoded['Response'] as List
          : (decoded is List ? decoded : const []);

      if (list.isEmpty) {
        debugPrint('[Description] API returned empty list');
        return;
      }

      final myPhone = _normalizePhone(_customer.phone);
      Map found = {};
      int? foundId;

      // 1) Prefer match by phone number
      for (final e in list) {
        if (e is Map) {
          final phone = (e['PhoneNumber'] ?? '').toString();
          if (_normalizePhone(phone) == myPhone && myPhone.isNotEmpty) {
            found = e;
            final idVal = e['Id'] ?? e['ID'] ?? e['CustomerId'] ?? e['CustomerID'] ?? e['id'];
            if (idVal != null) {
              foundId = idVal is int ? idVal : int.tryParse(idVal.toString());
            }
            break;
          }
        }
      }

      // 2) Fallback match by full name if phone match not found
      if (foundId == null) {
        final first = (_customer.name).trim().toLowerCase();
        final last = (_customer.surname).trim().toLowerCase();
        for (final e in list) {
          if (e is Map) {
            final name = (e['Name'] ?? '').toString().trim().toLowerCase();
            final surname = (e['Surname'] ?? '').toString().trim().toLowerCase();
            if (name == first && surname == last) {
              found = e;
              final idVal = e['Id'] ?? e['ID'] ?? e['CustomerId'] ?? e['CustomerID'] ?? e['id'];
              if (idVal != null) {
                foundId = idVal is int ? idVal : int.tryParse(idVal.toString());
              }
              break;
            }
          }
        }
      }

      if (foundId != null) {
        if (!mounted) return;
        setState(() => _serverId = foundId);
        debugPrint('[Description] serverId found via API: $foundId');
        // Save to local cache for offline use
        await _upsertServerIdInCache(foundId);
      } else {
        debugPrint('[Description] No matching customer found in API to resolve Id');
      }
    } catch (e) {
      debugPrint('[Description] Error loading serverId from API: $e');
    }
  }

  // Persist resolved serverId into local customers cache (if present)
  Future<void> _upsertServerIdInCache(int id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('customers');
      if (saved == null) return;

      final List<dynamic> list = json.decode(saved);
      final myPhone = _normalizePhone(_customer.phone);
      for (int i = 0; i < list.length; i++) {
        final m = Map<String, dynamic>.from(list[i]);
        final p = _normalizePhone((m['phone'] ?? '').toString());
        final byFields = (m['name'] ?? '') == _customer.name &&
            (m['surname'] ?? '') == _customer.surname &&
            (m['phone'] ?? '') == _customer.phone;

        if (p == myPhone || byFields) {
          m['serverId'] = id;
          list[i] = m;
          break;
        }
      }
      await prefs.setString('customers', json.encode(list));
    } catch (_) {}
  }

  void _prefillFromCustomer(Customer c) {
    _nameController.text = (c.name).trim();
    _surnameController.text = (c.surname).trim();
    _phoneController.text = (c.phone).trim();
    _addressController.text = (c.address ?? '').trim();
    _emailController.text = (c.email).trim();

    _existingImageBytes = c.imageBytes;
    _customEntries = (c.customEntries ?? [])
        .map<Map<String, String>>((e) => Map<String, String>.from(e))
        .toList();

    final g = (c.gender ?? '').trim().toLowerCase();
    if (g.startsWith('m')) {
      _gender = 'Male';
    } else if (g.startsWith('f')) _gender = 'Female';
    else if (g.isEmpty) _gender = null;
    else _gender = 'Other';

    _selectedDate = _parseDob(c.dob);
    _dobController.text = _selectedDate != null
        ? "${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}"
        : "";
  }

  Future<void> _loadServerIdFromCache(Customer c) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('customers');
    if (saved == null) return;
    try {
      final List<dynamic> list = json.decode(saved);
      for (final item in list) {
        if (item is Map) {
          final name = (item['name'] ?? '').toString();
          final surname = (item['surname'] ?? '').toString();
          final phone = (item['phone'] ?? '').toString();
          if (name == c.name && surname == c.surname && phone == c.phone) {
            final id = item['serverId'];
            if (id != null) {
              setState(() => _serverId = (id is int) ? id : int.tryParse(id.toString()));
            }
            break;
          }
        }
      }
    } catch (_) {}
  }

  DateTime? _parseDob(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final s = v.trim();
    try {
      if (s.contains('-')) return DateTime.tryParse(s);
      final p = s.split('/');
      if (p.length == 3) {
        final d = int.tryParse(p[0]) ?? 1;
        final m = int.tryParse(p[1]) ?? 1;
        final y = int.tryParse(p[2]) ?? 1970;
        return DateTime(y, m, d);
      }
    } catch (_) {}
    return null;
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey, fontSize: 16),
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 14),
      border: InputBorder.none,
    );
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _imageFile = File(picked.path));
  }

  Future<void> _pickDate() async {
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
  }

  String? _dobIso8601Z() {
    if (_selectedDate == null) return null;
    // Midday UTC to avoid TZ edge-cases
    final dt = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, 12, 0, 0);
    return dt.toUtc().toIso8601String();
  }

  String _othersAsString() {
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

  // ------------- Image compression helpers -------------
  Future<Uint8List?> _compressImageFromFile(
    File file, {
    int maxWidth = 1280,
    int maxHeight = 1280,
    int quality = 72,
  }) async {
    try {
      final compressed = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: maxWidth,
        minHeight: maxHeight,
        quality: quality,              // 0–100
        format: CompressFormat.jpeg,   // convert to JPEG
        keepExif: true,
      );
      return compressed;
    } catch (e) {
      debugPrint('Compression (file) failed: $e');
      try {
        return await file.readAsBytes();
      } catch (_) {
        return null;
      }
    }
  }

  Future<Uint8List> _compressImageFromBytes(
    Uint8List bytes, {
    int maxWidth = 1280,
    int maxHeight = 1280,
    int quality = 72,
  }) async {
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: maxWidth,
        minHeight: maxHeight,
        quality: quality,              // 0–100
        format: CompressFormat.jpeg,   // convert to JPEG
        keepExif: true,
      );
      return compressed;
    } catch (e) {
      debugPrint('Compression (bytes) failed: $e');
      return bytes;
    }
  }

  // Build HttpFileData with compressed image (JPEG)
  Future<Map<String, dynamic>> _buildHttpFileData() async {
    Uint8List? bytes;
    String fileName = "";
    String fileType = "jpg"; // compressed to JPEG

    if (_imageFile != null) {
      // Compress from file path (best for EXIF/orientation)
      final compressed = await _compressImageFromFile(_imageFile!);
      if (compressed != null && compressed.isNotEmpty) {
        bytes = compressed;
        final fn = _imageFile!.path.split(Platform.pathSeparator).last;
        fileName = fn.contains('.') ? fn.substring(0, fn.lastIndexOf('.')) : fn;
      }
    } else if (_existingImageBytes != null && _existingImageBytes!.isNotEmpty) {
      // Compress existing bytes if present
      final compressed = await _compressImageFromBytes(_existingImageBytes!);
      if (compressed.isNotEmpty) {
        bytes = compressed;
        fileName = "image";
      }
    }

    if (bytes == null || bytes.isEmpty) {
      // No image to send
      return {
        "FileName": "",
        "FileType": "",
        "FileData": "",
      };
    }

    final b64 = base64Encode(bytes);

    return {
      "FileName": fileName,
      "FileType": fileType, // 'jpg' after compression
      "FileData": b64,
    };
  }

  Future<String?> _resolveToken() async {
    final dynamic t = TokenStorage.getToken();
    if (t is Future) return await t;
    return t as String?;
  }

  // PUT /CustomerDataM/UpdateAsync
  Future<Map<String, dynamic>> _putCustomerUpdate({
    required int id,
    required String name,
    required String surname,
    required String phoneNumber,
    required String emailId,
    required String address,
    required String gender, // TitleCase expected
    required String others,
    required String? dobIsoZ,
    required int fileId,
    required Map<String, dynamic> httpFileData,
  }) async {
    final token = await _resolveToken();

    // Build payload
    final payload = <String, dynamic>{
      "Id": id,
      "Name": name,
      "Surname": surname,
      "PhoneNumber": phoneNumber,
      "FileId": fileId,
      "EmailId": emailId,
      "Address": address,
      "Gender": gender, // TitleCase
      "Others": others,
    };
    if (dobIsoZ != null && dobIsoZ.isNotEmpty) {
      payload["DOB"] = dobIsoZ;
    }
    final fileDataStr = (httpFileData["FileData"] as String?)?.trim() ?? "";
    if (fileDataStr.isNotEmpty) {
      payload["HttpFileData"] = httpFileData;
      if ((payload["FileId"] as int) <= 0) {
        payload["FileId"] = 0; // typical for "replace with new file"
      }
    }

    final headers = <String, String>{
      "Content-Type": "application/json; charset=utf-8",
      "Accept": "application/json, text/plain, */*",
      if (token != null && token.isNotEmpty) "Authorization": "Bearer $token",
    };

    final candidates = <String>[
      '$_apiBaseWithApi/CustomerDataM/UpdateAsync',
      '${_apiBaseUrl.trim().replaceAll(RegExp(r"/+$"), "")}/CustomerDataM/UpdateAsync',
    ];

    http.Response? last;
    for (final url in candidates) {
      try {
        debugPrint('[Edit] PUT $url');
        debugPrint('[Edit] Payload: ${jsonEncode(payload)}');

        final res = await http.put(Uri.parse(url), headers: headers, body: jsonEncode(payload));
        debugPrint('[Edit] <- ${res.statusCode} ${res.body}');

        if (res.statusCode >= 200 && res.statusCode < 300) {
          final body = res.body.trim();
          if (body.isEmpty) return {};
          try {
            final decoded = jsonDecode(body);
            if (decoded is Map<String, dynamic>) return decoded;
            if (decoded is List && decoded.isNotEmpty && decoded.first is Map<String, dynamic>) {
              return decoded.first as Map<String, dynamic>;
            }
          } catch (_) {
            return {"message": body, "status": res.statusCode};
          }
          return {};
        }

        last = res;
        if (res.statusCode == 404) {
          debugPrint('[Edit] 404 at $url, trying next candidate...');
          continue;
        } else {
          final msg = _extractServerError(res.body) ?? 'Server error ${res.statusCode}';
          throw Exception(msg);
        }
      } catch (e) {
        debugPrint('[Edit] PUT failed for $url: $e');
      }
    }

    if (last != null) {
      final msg = _extractServerError(last.body) ?? 'Server error ${last.statusCode}';
      throw Exception(msg);
    }
    throw Exception('No reachable Update endpoint (all candidates failed)');
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

  Future<void> _saveChanges() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Name is required")));
      return;
    }
    if (_serverId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Missing server Id for update")));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final httpFileData = await _buildHttpFileData();
      final others = _othersAsString();
      final dobIsoZ = _dobIso8601Z();

      final genderTitle = _gender ?? '';

      await _putCustomerUpdate(
        id: _serverId!,
        name: _nameController.text.trim(),
        surname: _surnameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        emailId: _emailController.text.trim(),
        address: _addressController.text.trim(),
        gender: genderTitle,
        others: others,
        dobIsoZ: dobIsoZ,
        fileId: 0,
        httpFileData: httpFileData,
      );

      // update local cache and state
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString('customers');

      // Use the compressed bytes we just sent for local cache
      Uint8List? updatedBytes;
      final b64 = (httpFileData['FileData'] as String?)?.trim();
      if (b64 != null && b64.isNotEmpty) {
        try {
          updatedBytes = base64Decode(b64);
        } catch (_) {
          // fallback to original picked image bytes if decode fails
          if (_imageFile != null) {
            try {
              updatedBytes = await _imageFile!.readAsBytes();
            } catch (_) {}
          } else {
            updatedBytes = _existingImageBytes;
          }
        }
      } else {
        updatedBytes = _existingImageBytes;
      }

      if (existing != null) {
        final List<dynamic> list = json.decode(existing);
        for (int i = 0; i < list.length; i++) {
          final m = Map<String, dynamic>.from(list[i]);
          final matchById = (m['serverId']?.toString() ?? '') == _serverId!.toString();
          final matchByFields = (m['name'] ?? '') == widget.customer.name &&
              (m['surname'] ?? '') == widget.customer.surname &&
              (m['phone'] ?? '') == widget.customer.phone;
          if (matchById || matchByFields) {
            m['name'] = _nameController.text.trim();
            m['surname'] = _surnameController.text.trim();
            m['phone'] = _phoneController.text.trim();
            m['email'] = _emailController.text.trim();
            m['address'] = _addressController.text.trim();
            m['dob'] = _dobController.text.trim();
            m['gender'] = (genderTitle).toLowerCase();
            m['customEntries'] = _customEntries;
            m['serverId'] = _serverId;
            if (updatedBytes != null) {
              m['imageBytes'] = base64Encode(updatedBytes);
            }
            if (_imageFile != null) {
              m['photo'] = _imageFile!.path;
            }
            list[i] = m;
            break;
          }
        }
        await prefs.setString('customers', json.encode(list));
      }

      setState(() {
        _customer = Customer(
          name: _nameController.text.trim(),
          surname: _surnameController.text.trim(),
          phone: _phoneController.text.trim(),
          email: _emailController.text.trim(),
          address: _addressController.text.trim(),
          dob: _dobController.text.trim(),
          gender: (genderTitle).toLowerCase(),
          customEntries: _customEntries,
          photo: _imageFile?.path,
          imageBytes: updatedBytes,
        );
        _existingImageBytes = updatedBytes;
        _isEditing = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Customer updated successfully")));
      Navigator.pop(context, _customer); // return updated to caller
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _deleteCustomer() async {
    final prefs = await SharedPreferences.getInstance();
    final customersJson = prefs.getString('customers');
    if (customersJson != null) {
      List<dynamic> list = json.decode(customersJson);
      list.removeWhere((item) {
        final m = Map<String, dynamic>.from(item);
        final matchById = (m['serverId']?.toString() ?? '') == (_serverId?.toString() ?? '');
        final matchByFields = m['name'] == _customer.name && m['surname'] == _customer.surname && m['phone'] == _customer.phone;
        return matchById || matchByFields;
      });

      await prefs.setString('customers', json.encode(list));

      final lastUserJson = prefs.getString('last_user');
      if (lastUserJson != null) {
        final lastUser = json.decode(lastUserJson);
        final match = (lastUser['name'] == _customer.name &&
            lastUser['surname'] == _customer.surname &&
            lastUser['phone'] == _customer.phone);
        if (match) await prefs.remove('last_user');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Customer deleted locally")));
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  Future<void> _shareCustomerInfo() async {
    String safe(String? s) => (s ?? '').trim();
    final buffer = StringBuffer()
      ..writeln('👤 ${safe(_customer.name)} ${safe(_customer.surname)}')
      ..writeln('📧 ${safe(_customer.email)}')
      ..writeln('📱 ${safe(_customer.phone)}')
      ..writeln('🏠 ${safe(_customer.address)}')
      ..writeln('🎂 ${safe(_customer.dob)}')
      ..writeln('⚧️ ${safe(_customer.gender)}');

    final entries = _customer.customEntries ?? [];
    if (entries.isNotEmpty) {
      buffer.writeln('\nCustom Entries:');
      for (final entry in entries) {
        final type = safe(entry['type']?.toString());
        final detail = safe(entry['detail']?.toString());
        buffer.writeln('• $type: $detail');
      }
    }
    await Share.share(buffer.toString());
  }

  @override
  Widget build(BuildContext context) {
    final avatarProvider = _imageFile != null
        ? FileImage(_imageFile!)
        : (_existingImageBytes != null ? MemoryImage(_existingImageBytes!) as ImageProvider : null);

    final entries = _customer.customEntries ?? [];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Customer Details"),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage("assets/images/Background2.jpeg"),
              fit: BoxFit.cover,
            ),
          ),
        ),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white),
              tooltip: "Edit",
              onPressed: () => setState(() => _isEditing = true),
            ),
          if (_isEditing)
            IconButton(
              icon: _isSubmitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save, color: Colors.white),
              tooltip: "Save",
              onPressed: _isSubmitting ? null : _saveChanges,
            ),
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: "Cancel",
              onPressed: _isSubmitting
                  ? null
                  : () {
                      setState(() {
                        _isEditing = false;
                        _imageFile = null; // discard picked image
                        _prefillFromCustomer(_customer); // reset fields
                      });
                    },
            ),
          if (!_isEditing)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'share') {
                  _shareCustomerInfo();
                } else if (value == 'delete') {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text("Delete Customer"),
                      content: const Text("Are you sure you want to delete this customer locally?"),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _deleteCustomer();
                          },
                          child: const Text("Delete", style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'share', child: Text("Share Info")),
                PopupMenuItem(value: 'delete', child: Text("Delete", style: TextStyle(color: Colors.red))),
              ],
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: _isEditing ? _buildEditForm(avatarProvider, entries) : _buildReadOnlyView(avatarProvider, entries),
      ),
      bottomNavigationBar: !_isEditing
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, _customer),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Close", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildReadOnlyView(ImageProvider? avatarProvider, List<Map<String, String>> entries) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: CircleAvatar(
            radius: 70,
            backgroundColor: Colors.grey.shade200,
            backgroundImage: avatarProvider,
            child: avatarProvider == null ? const Icon(Icons.person, size: 50, color: Colors.grey) : null,
          ),
        ),
        const SizedBox(height: 30),
        _detailRow("Full Name", "${_customer.name} ${_customer.surname}"),
        _detailRow("Email", _customer.email),
        _detailRow("Phone", _customer.phone),
        if (entries.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text("Custom Entries", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: entries.map((entry) {
              final type = (entry['type'] ?? '').toString();
              final detail = (entry['detail'] ?? '').toString();
              return Chip(
                label: Text("$type: $detail"),
                backgroundColor: Colors.blue.shade50,
                avatar: const Icon(Icons.label, size: 16, color: Colors.blue),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildEditForm(ImageProvider? avatarProvider, List<Map<String, String>> entries) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: GestureDetector(
            onTap: _pickImage,
            child: CircleAvatar(
              radius: 70,
              backgroundColor: Colors.grey.shade200,
              backgroundImage: avatarProvider,
              child: avatarProvider == null ? const Icon(Icons.person, size: 50, color: Colors.grey) : null,
            ),
          ),
        ),
        const SizedBox(height: 24),
        TextField(controller: _nameController, decoration: _inputDecoration("Name")),
        const Divider(color: Colors.black12),
        TextField(controller: _surnameController, decoration: _inputDecoration("Surname")),
        const Divider(color: Colors.black12),
        TextField(
          controller: _dobController,
          readOnly: true,
          onTap: _pickDate,
          decoration: _inputDecoration("Date of Birth").copyWith(
            suffixIcon: const Icon(Icons.calendar_today, color: Colors.black54),
          ),
        ),
        const Divider(color: Colors.black12),
        TextField(controller: _emailController, decoration: _inputDecoration("Email")),
        const Divider(color: Colors.black12),
        TextField(controller: _phoneController, decoration: _inputDecoration("Phone No")),
        const Divider(color: Colors.black12),
        TextField(controller: _addressController, decoration: _inputDecoration("Address")),
        const Divider(color: Colors.black12),
        const SizedBox(height: 12),
        const Text("Gender", style: TextStyle(color: Colors.grey)),
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
        if (entries.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text("Custom Entries (read-only here)"),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: entries
                .map((e) => Chip(
                      label: Text("${e['type'] ?? ''}: ${e['detail'] ?? ''}"),
                      backgroundColor: Colors.grey.shade200,
                    ))
                .toList(),
          ),
        ],
        const SizedBox(height: 90),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    final safeValue = (value).trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          safeValue.isEmpty ? "Not provided" : safeValue,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
        ),
        const Divider(color: Colors.black12, height: 30),
      ],
    );
  }
}