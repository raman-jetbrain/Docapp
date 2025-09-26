import 'dart:convert';
import 'dart:io';
import 'package:docapp/api/api_constant.dart';
import 'package:docapp/model/customermodel.dart';
import 'package:docapp/storage/Token_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class AddNewUserPage extends StatefulWidget {
  const AddNewUserPage({super.key,});

  @override
  State<AddNewUserPage> createState() => _AddNewUserPageState();
}

class _AddNewUserPageState extends State<AddNewUserPage> {
  static const Color kPrimaryBlue = Color(0xFF38B6E4);
  static const double kScreenPadding = 18;

  // Read from ApiConstants (with or without /api)
  static String get _apiBaseUrl => ApiConstants.baseUrl;

  // Normalize base URL so '/api' exists only once and no trailing slash.
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

  DateTime? _selectedDate;
  String? _gender;
  List<Map<String, String>> _customEntries = [];

  bool _isSubmitting = false;

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
    if (pickedFile != null) {
      setState(() => _imageFile = File(pickedFile.path));
    }
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

  // Returns ISO-8601 UTC string: "2025-09-24T12:14:07.978Z"
  String? _dobIso8601Z() {
    if (_selectedDate == null) return null;
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

  Map<String, dynamic> _buildHttpFileData() {
    // Default shape if no file is picked
    Map<String, dynamic> data = {
      "StatusCode": 100,
      "Message": "done",
      "FileName": "",
      "FileType": "",
      "FileData": "",
    };

    if (_imageFile == null) return data;

    try {
      final bytes = _imageFile!.readAsBytesSync();
      final b64 = base64Encode(bytes);

      final path = _imageFile!.path;
      final fileNameOnly = path.split(Platform.pathSeparator).last;
      final dot = fileNameOnly.lastIndexOf('.');
      final nameNoExt = dot > 0 ? fileNameOnly.substring(0, dot) : fileNameOnly;
      final ext = dot > 0 ? fileNameOnly.substring(dot + 1) : "";

      data = {
        "StatusCode": 100,
        "Message": "done",
        "FileName": nameNoExt.isNotEmpty ? nameNoExt : "file",
        "FileType": ext.isNotEmpty ? ext : "image",
        "FileData": b64, // If backend expects text (e.g., Aadhaar), replace with that string
      };
    } catch (_) {
      // Keep default if any error
    }
    return data;
  }

  // ---------- Local auto-increment ID helpers ----------
  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    if (v is double) return v.toInt();
    return null;
  }

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
            final server = _toInt(item['serverId']);
            if (local != null && local > maxId) maxId = local;
            if (server != null && server > maxId) maxId = server;
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

  // EXACT payload with endpoint fallback and logging; returns on first 2xx.
  Future<Map<String, dynamic>> _createCustomerOnServerExactPayload({
    required String name,
    required String surname,
    required String phoneNumber,
    required String emailId,
    required String address,
    required String gender, // lowercased later
    required String others, // string
    required String? dobIsoZ,
    required int id,
    required int fileId,
    required Map<String, dynamic> httpFileData,
  }) async {
    final token = await TokenStorage.getToken();

    final payload = <String, dynamic>{
      "Id": id, // If your backend needs 0 for create, set it here
      "Name": name,
      "Surname": surname,
      "PhoneNumber": phoneNumber,
      "FileId": fileId, // Use positive ID if backend validates it
      "EmailId": emailId,
      "Address": address,
      "Gender": gender.toLowerCase(),
      "Others": others,
      "DOB": dobIsoZ ?? DateTime.now().toUtc().toIso8601String(),
      "SDOB": dobIsoZ ?? DateTime.now().toUtc().toIso8601String(),
      "HttpFileData": httpFileData,
    };

    final headers = <String, String>{
      "Content-Type": "application/json; charset=utf-8",
      "Accept": "application/json",
      if (token != null && token.isNotEmpty) "Authorization": "Bearer $token",
    };
    
    // Try likely routes in order and stop on first 2xx
    final candidates = <String>[
      '$_apiBaseNormalized/CustomerDataM',              // RESTful POST
      '$_apiBaseNormalized/CustomerDataM/AddAsync',     // action-based route
      '$_apiBaseNormalized/customerDataM',
      '$_apiBaseNormalized/customerDataM/AddAsync',
    ];

    http.Response? last;
    for (final url in candidates) {
      try {
        debugPrint('[Add] POST $url');
        debugPrint('[Add] Payload: ${jsonEncode(payload)}');

        final res = await http.post(Uri.parse(url), headers: headers, body: jsonEncode(payload));
        debugPrint('[Add] <- ${res.statusCode} ${res.body}');

        if (res.statusCode >= 200 && res.statusCode < 300) {
          debugPrint('[Add] SUCCESS: ${res.statusCode} for $url'); // Will print 200 on success
          final body = res.body.trim();
          if (body.isEmpty) return {};
          final decoded = jsonDecode(body);
          if (decoded is Map<String, dynamic>) return decoded;
          if (decoded is List && decoded.isNotEmpty && decoded.first is Map<String, dynamic>) {
            return decoded.first as Map<String, dynamic>;
          }
          return {};
        }

        last = res;
        if (res.statusCode == 404) {
          debugPrint('[Add] 404 at $url, trying next candidate...');
          continue;
        } else {
          final msg = _extractServerError(res.body) ?? 'Server error ${res.statusCode}';
          throw Exception(msg);
        }
      } catch (e) {
        debugPrint('[Add] POST failed for $url: $e');
        // Try next candidate
      }
    }

    if (last != null) {
      final msg = _extractServerError(last.body) ?? 'Server error ${last.statusCode}';
      throw Exception(msg);
    }
    throw Exception('No reachable Add endpoint (all candidates failed)');
  }

  // Optional GET tester
  Future<void> debugFetchCustomers() async {
    final url = '$_apiBaseNormalized/CustomerDataM/GetAsync';
    final token = await TokenStorage.getToken();
    final res = await http.get(
      Uri.parse(url),
      headers: {
        "Accept": "application/json",
        if (token != null && token.isNotEmpty) "Authorization": "Bearer $token",
      },
    );
    debugPrint("GET $url -> ${res.statusCode}");
    debugPrint(res.body);
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

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Name is required")));
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    try {
      final localId = await _peekNextLocalCustomerId();

      // Build exact payload parts
      final dobIsoZ = _dobIso8601Z();
      final others = _othersAsString();
      final httpFileData = _buildHttpFileData();

      final serverResponse = await _createCustomerOnServerExactPayload(
        id: localId, // If server needs 0, change here
        name: _nameController.text.trim(),
        surname: _surnameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        emailId: _emailController.text.trim(),
        address: _addressController.text.trim(),
        gender: _gender?.trim() ?? "",
        others: others,
        dobIsoZ: dobIsoZ,
        fileId: 1, // Use positive id if backend validates this
        httpFileData: httpFileData,
      );

      // Cache locally
      final bytes = _imageFile != null ? await _imageFile!.readAsBytes() : null;
      final imageB64 = bytes != null ? base64Encode(bytes) : null;

      final newCustomerMap = {
        "localId": localId,
        "name": _nameController.text.trim(),
        "surname": _surnameController.text.trim(),
        "phone": _phoneController.text.trim(),
        "address": _addressController.text.trim(),
        "email": _emailController.text.trim(),
        "dob": _dobController.text.trim(),
        "gender": (_gender ?? "").toLowerCase(),
        "customEntries": _customEntries,
        "serverId": serverResponse['Id'] ?? serverResponse['id'],
        "photo": _imageFile?.path ?? "",
        if (imageB64 != null) "imageBytes": imageB64,
      };

      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString('customers');
      final List<dynamic> list = existing != null ? json.decode(existing) : [];
      list.add(newCustomerMap);

      await prefs.setString('customers', json.encode(list));
      await prefs.setString('last_user', json.encode(newCustomerMap));
      await _advanceNextLocalCustomerId(localId);

      if (!mounted) return;

      Navigator.pop(
        context,
        Customer(
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
          photo: newCustomerMap['photo'] as String?,
          imageBytes: bytes,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Submit failed: $e")),
      );
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
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                      onTap: _pickDate,
                      decoration: _inputDecoration("Date of Birth").copyWith(
                        suffixIcon: const Icon(Icons.keyboard_arrow_down, color: Colors.black54),
                      ),
                    ),
                    const Divider(color: Colors.black12),
                    TextField(controller: _emailController, decoration: _inputDecoration("Email")),
                    const Divider(color: Colors.black12),
                    TextField(controller: _phoneController, decoration: _inputDecoration("Phone No")),
                    const Divider(color: Colors.black12),
                    TextField(controller: _addressController, decoration: _inputDecoration("Address")),
                    const Divider(color: Colors.black12),
                    const SizedBox(height: 20),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text("Gender", style: TextStyle(color: Colors.grey)),
                    ),
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
                    ElevatedButton.icon(
                      onPressed: _showAddCustomEntryDialog,
                      icon: Icon(Icons.add, color: kPrimaryBlue),
                      label: Text("Add Custom Entry", style: TextStyle(color: kPrimaryBlue)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        elevation: 0,
                        side: const BorderSide(color: kPrimaryBlue),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
              )
            ]),
          )
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _isSubmitting
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