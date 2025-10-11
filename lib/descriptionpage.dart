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
import 'package:path/path.dart' as p;

// ================== DescriptionPage ==================
class DescriptionPage extends StatefulWidget {
  final Customer customer;
  const DescriptionPage({super.key, required this.customer});

  @override
  State<DescriptionPage> createState() => _DescriptionPageState();
}

class _DescriptionPageState extends State<DescriptionPage> {
  // Brand/style (matching your Documents style)
  static const Color kPrimaryBlue = Color(0xFF38B6E4);
  Color get borderColor => Colors.black;
  Color get iconColor => Colors.black;

  // API base
  static String get _apiBaseUrl => ApiConstants.baseUrl;
  String get _apiBaseWithApi {
    var b = _apiBaseUrl.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    if (!b.toLowerCase().endsWith('/api')) b = '$b/api';
    return b;
  }

  String get _baseWithoutApi {
    var b = _apiBaseUrl.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    if (b.toLowerCase().endsWith('/api')) {
      b = b.substring(0, b.length - 4);
    }
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    return b;
  }

  // State
  bool _isLoading = false;
  bool _isSubmitting = false;

  // Per-container edit flags
  bool _editProfile = false; // image
  bool _editIdentity = false; // name, surname, gender
  bool _editContact = false; // phone, email
  bool _editAddress = false; // address
  bool _editDates = false; // DOB
  bool _editOthers = false; // others

  // Controllers
  final _nameCtrl = TextEditingController();
  final _surnameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _othersCtrl = TextEditingController();

  // Identity
  String? _gender; // Male / Female / Other

  // Dates
  DateTime? _selectedDate; // DOB
  String? _sdobIso; // SDOB from server (display only)

  // Image/profile
  final ImagePicker _picker = ImagePicker();
  File? _imageFile; // picked new image file
  Uint8List? _avatarBytes; // display bytes for profile
  String? _avatarUrl; // HttpFileData.FileName resolved (not shown in UI)
  int? _fileId; // server FileId
  int? _httpFileId; // server HttpFileData.Id

  // Server record + Documents
  Map<String, dynamic>? _serverRecord;
  List<_ServerDoc> _serverDocs = [];

  // IDs
  int? _serverId;

  // Local model
  late Customer _customer;

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    _prefillFromLocal(_customer);
    _resolveServerIdThenFetch();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _surnameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _dobCtrl.dispose();
    _othersCtrl.dispose();
    super.dispose();
  }

  // ------------------------ Resolve Id and Fetch ------------------------

  Future<void> _resolveServerIdThenFetch() async {
    await _loadServerIdFromCache();
    if (_serverId == null) await _loadServerIdFromList();
    if (_serverId != null) await _fetchCustomerById(_serverId!);
  }

  Future<void> _loadServerIdFromCache() async {
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
          if (name == _customer.name &&
              surname == _customer.surname &&
              phone == _customer.phone) {
            final id = item['serverId'];
            if (id != null)
              setState(
                () =>
                    _serverId = (id is int) ? id : int.tryParse(id.toString()),
              );
            break;
          }
        }
      }
    } catch (_) {}
  }

  String _normPhone(String s) => s.replaceAll(RegExp(r'\D+'), '');

  Future<void> _loadServerIdFromList() async {
    try {
      final token = await _resolveToken();
      if (token == null || token.isEmpty) return;
      final url = '$_apiBaseWithApi/CustomerDataM/GetAsync';
      final res = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (res.statusCode < 200 || res.statusCode >= 300) return;

      final decoded = jsonDecode(res.body);
      final List<dynamic> list = decoded is Map && decoded['Response'] is List
          ? decoded['Response'] as List
          : (decoded is List ? decoded : const []);

      int? foundId;
      final myPhone = _normPhone(_customer.phone);

      // 1) By phone
      for (final e in list) {
        if (e is Map) {
          final ph = (e['PhoneNumber'] ?? '').toString();
          if (_normPhone(ph) == myPhone && myPhone.isNotEmpty) {
            final idVal =
                e['Id'] ??
                e['ID'] ??
                e['CustomerId'] ??
                e['CustomerID'] ??
                e['id'];
            if (idVal != null)
              foundId = idVal is int ? idVal : int.tryParse(idVal.toString());
            break;
          }
        }
      }
      // 2) By name + surname
      if (foundId == null) {
        final first = _customer.name.trim().toLowerCase();
        final last = _customer.surname.trim().toLowerCase();
        for (final e in list) {
          if (e is Map) {
            final name = (e['Name'] ?? '').toString().trim().toLowerCase();
            final surname = (e['Surname'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            if (name == first && surname == last) {
              final idVal =
                  e['Id'] ??
                  e['ID'] ??
                  e['CustomerId'] ??
                  e['CustomerID'] ??
                  e['id'];
              if (idVal != null)
                foundId = idVal is int ? idVal : int.tryParse(idVal.toString());
              break;
            }
          }
        }
      }

      if (foundId != null) {
        setState(() => _serverId = foundId);
        await _upsertIdInCache(foundId);
      }
    } catch (_) {}
  }

  Future<void> _upsertIdInCache(int id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('customers');
      if (saved == null) return;
      final List<dynamic> list = json.decode(saved);
      for (int i = 0; i < list.length; i++) {
        final m = Map<String, dynamic>.from(list[i]);
        if ((m['name'] ?? '') == _customer.name &&
            (m['surname'] ?? '') == _customer.surname &&
            (m['phone'] ?? '') == _customer.phone) {
          m['serverId'] = id;
          list[i] = m;
          break;
        }
      }
      await prefs.setString('customers', json.encode(list));
    } catch (_) {}
  }

  Future<void> _fetchCustomerById(int id) async {
    setState(() => _isLoading = true);
    try {
      final token = await _resolveToken();
      if (token == null || token.isEmpty) return;
      final url = '$_apiBaseWithApi/CustomerDataM/GetAsync/$id';
      final res = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (res.statusCode < 200 || res.statusCode >= 300) return;

      final decoded = jsonDecode(res.body);
      final record = _unwrapApi(decoded);
      if (record.isEmpty) return;

      _applyServerRecord(record);
      await _upsertIdInCache(id);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _unwrapApi(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      final r = raw['Response'];
      if (r is Map<String, dynamic>) return r;
      if (r is List && r.isNotEmpty && r.first is Map)
        return Map<String, dynamic>.from(r.first as Map);
      return raw;
    }
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return Map<String, dynamic>.from(raw.first as Map);
    }
    return {};
  }

  // ------------------------ Apply record ------------------------

  void _applyServerRecord(Map<String, dynamic> r) {
    _serverRecord = r;

    // Identity
    _nameCtrl.text = (r['Name'] ?? '').toString();
    _surnameCtrl.text = (r['Surname'] ?? '').toString();
    final g = (r['Gender'] ?? '').toString().trim().toLowerCase();
    if (g.startsWith('m'))
      _gender = 'Male';
    else if (g.startsWith('f'))
      _gender = 'Female';
    else if (g.isEmpty)
      _gender = null;
    else
      _gender = 'Other';

    // Contact
    _phoneCtrl.text = (r['PhoneNumber'] ?? '').toString();
    _emailCtrl.text = (r['EmailId'] ?? '').toString();

    // Address
    _addressCtrl.text = (r['Address'] ?? '').toString();

    // Dates
    final dobIso = (r['DOB'] ?? '').toString();
    _selectedDate = _parseIso(dobIso);
    _dobCtrl.text = _selectedDate != null ? _fmt(_selectedDate!) : '';
    _sdobIso = (r['SDOB'] ?? '').toString();

    // Others
    _othersCtrl.text = (r['Others'] ?? '').toString();

    // File info
    final fileIdVal = r['FileId'];
    final httpFileData = r['HttpFileData'];
    final httpFileIdVal = (httpFileData is Map) ? httpFileData['Id'] : null;
    _fileId = fileIdVal is int
        ? fileIdVal
        : int.tryParse((fileIdVal ?? '').toString());
    _httpFileId = httpFileIdVal is int
        ? httpFileIdVal
        : int.tryParse((httpFileIdVal ?? '').toString());

    // Profile image URL (not displayed as text)
    String fn = '';
    bool isDeleted = false;
    if (httpFileData is Map) {
      fn = (httpFileData['FileName'] ?? '').toString();
      isDeleted = (httpFileData['IsDeleted'] ?? false) == true;
    }
    _avatarUrl = (fn.isNotEmpty && !isDeleted) ? _resolveFileUrl(fn) : null;

    // Load avatar bytes from URL if not present/local
    if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      _fetchBytesWithAuth(_avatarUrl!).then((b) {
        if (!mounted) return;
        if (b != null && b.isNotEmpty) setState(() => _avatarBytes = b);
      });
    }

    // Documents list
    _serverDocs = [];
    final docs = r['Documents'];
    if (docs is List) {
      for (final e in docs) {
        if (e is Map) {
          final m = Map<String, dynamic>.from(e);
          final id = (m['Id'] ?? m['id'] ?? 0).toString();
          final remarks = (m['Remarks'] ?? m['remarks'] ?? '').toString();
          final fileName = (m['FileName'] ?? m['fileName'] ?? '').toString();
          final fileType = (m['FileType'] ?? m['fileType'] ?? '').toString();
          final urlStrRaw = (m['Url'] ?? m['url'] ?? fileName).toString();
          final urlStr = urlStrRaw.isNotEmpty ? _resolveFileUrl(urlStrRaw) : '';
          _serverDocs.add(
            _ServerDoc(
              id: id,
              remarks: remarks,
              fileName: fileName.isNotEmpty ? fileName : urlStrRaw,
              fileType: fileType,
              url: urlStr.isNotEmpty ? urlStr : null,
            ),
          );
        }
      }
    }

    setState(() {});
  }

  // ------------------------ UI helpers ------------------------

  void _prefillFromLocal(Customer c) {
    _nameCtrl.text = c.name;
    _surnameCtrl.text = c.surname;
    _phoneCtrl.text = c.phone;
    _emailCtrl.text = c.email;
    _addressCtrl.text = c.address ?? '';
    _avatarBytes = c.imageBytes;

    final g = (c.gender ?? '').trim().toLowerCase();
    if (g.startsWith('m'))
      _gender = 'Male';
    else if (g.startsWith('f'))
      _gender = 'Female';
    else if (g.isEmpty)
      _gender = null;
    else
      _gender = 'Other';

    final dob = _parseLocalDob(c.dob);
    _selectedDate = dob;
    _dobCtrl.text = dob != null ? _fmt(dob) : '';
    _othersCtrl.text = '';
  }

  DateTime? _parseLocalDob(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    if (v.contains('-')) return DateTime.tryParse(v);
    final p = v.split('/');
    if (p.length == 3) {
      final d = int.tryParse(p[0]) ?? 1;
      final m = int.tryParse(p[1]) ?? 1;
      final y = int.tryParse(p[2]) ?? 1970;
      return DateTime(y, m, d);
    }
    return null;
  }

  DateTime? _parseIso(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    try {
      return DateTime.tryParse(v);
    } catch (_) {
      return null;
    }
  }

  String _fmt(DateTime dt) =>
      "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}";

  // Build full file URL
  String _resolveFileUrl(String fileNameOrUrl) {
    if (fileNameOrUrl.isEmpty) return fileNameOrUrl;
    final u = fileNameOrUrl.trim();
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    if (u.startsWith('/')) return '$_baseWithoutApi$u';
    return '$_baseWithoutApi/$u';
  }

  bool _isImageUrlOrType(String? mimeOrUrl) {
    if (mimeOrUrl == null) return false;
    final s = mimeOrUrl.toLowerCase();
    if (s.startsWith('image/')) return true;
    final ext = p.extension(s);
    return [
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.bmp',
      '.tif',
      '.tiff',
      '.heic',
    ].contains(ext);
    // If URL without extension and no mime, we won't assume it's image.
  }

  Future<Uint8List?> _fetchBytesWithAuth(String url) async {
    try {
      final token = await _resolveToken();
      final headers = <String, String>{'Accept': '*/*'};
      if (token != null && token.isNotEmpty)
        headers['Authorization'] = 'Bearer $token';
      final res = await http.get(Uri.parse(url), headers: headers);
      if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
    } catch (_) {}
    return null;
  }

  String _initials(String name, String surname) {
    final a = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '';
    final b = surname.trim().isNotEmpty ? surname.trim()[0].toUpperCase() : '';
    final s = (a + b).trim();
    return s.isEmpty ? '?' : s;
  }

  // ------------------------ Picking and Saving ------------------------

  Future<void> _pickImageFrom(ImageSource src) async {
    final picked = await _picker.pickImage(source: src);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _imageFile = File(picked.path);
      _avatarBytes = bytes; // show immediately
    });
  }

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
        quality: quality,
        format: CompressFormat.jpeg,
        keepExif: true,
      );
      return compressed;
    } catch (_) {
      try {
        return await file.readAsBytes();
      } catch (_) {
        return null;
      }
    }
  }

  Future<Map<String, dynamic>> _buildHttpFileData({
    required int customerId,
    required int httpFileId,
  }) async {
    Uint8List? bytes;
    String fileName = "";
    String fileType = "jpg";

    if (_imageFile != null) {
      final compressed = await _compressImageFromFile(_imageFile!);
      if (compressed != null && compressed.isNotEmpty) {
        bytes = compressed;
        final fn = _imageFile!.path.split(Platform.pathSeparator).last;
        fileName = fn.contains('.') ? fn.substring(0, fn.lastIndexOf('.')) : fn;
      }
    }

    final isModified = bytes != null && bytes.isNotEmpty;
    final b64 = isModified ? base64Encode(bytes!) : "";

    return {
      "Id": httpFileId,
      "IsModified": isModified,
      "FileData": b64,
      "FileName": isModified ? fileName : "",
      "FileType": isModified ? fileType : "",
      "Remarks": (_serverRecord?['HttpFileData']?['Remarks'] ?? '').toString(),
      "IsDeleted": false,
      "CustomerDataId": customerId,
    };
  }

  Future<Map<String, dynamic>> _putCustomerUpdate({
    required int id,
    required String name,
    required String surname,
    required String phoneNumber,
    required String emailId,
    required String address,
    required String gender,
    required String others,
    required String? dobIsoZ,
    required int fileId,
    required Map<String, dynamic> httpFileData,
  }) async {
    final token = await _resolveToken();

    final payload = <String, dynamic>{
      "Id": id,
      "ParentCustomerDataId":
          (_serverRecord?['ParentCustomerDataId'] ?? 0) as int,
      "Name": name,
      "Surname": surname,
      "PhoneNumber": phoneNumber,
      "FileId": fileId,
      "EmailId": emailId,
      "Address": address,
      "Gender": gender,
      "Others": others,
      "ChildDatas": <dynamic>[],
    };

    if (dobIsoZ != null && dobIsoZ.isNotEmpty) {
      payload["DOB"] = dobIsoZ;
      payload["SDOB"] = dobIsoZ;
    }

    payload["HttpFileData"] = httpFileData;
    final docs = <Map<String, dynamic>>[];
    final isModified = (httpFileData["IsModified"] as bool?) ?? false;
    if (isModified) docs.add(Map<String, dynamic>.from(httpFileData));
    payload["Documents"] = docs;

    final headers = <String, String>{
      "Content-Type": "application/json; charset=utf-8",
      "Accept": "application/json",
      if (token != null && token.isNotEmpty) "Authorization": "Bearer $token",
    };

    final candidates = <String>[
      '$_apiBaseWithApi/CustomerDataM/UpdateAsync',
      '${_apiBaseUrl.trim().replaceAll(RegExp(r"/+$"), "")}/CustomerDataM/UpdateAsync',
    ];

    http.Response? last;
    for (final url in candidates) {
      try {
        final res = await http.put(
          Uri.parse(url),
          headers: headers,
          body: jsonEncode(payload),
        );
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final body = res.body.trim();
          if (body.isEmpty) return {};
          try {
            final decoded = jsonDecode(body);
            if (decoded is Map<String, dynamic>) return decoded;
            if (decoded is List &&
                decoded.isNotEmpty &&
                decoded.first is Map<String, dynamic>) {
              return decoded.first as Map<String, dynamic>;
            }
          } catch (_) {
            return {"message": body, "status": res.statusCode};
          }
          return {};
        }
        last = res;
        if (res.statusCode == 404) continue;
        final msg =
            _extractServerError(res.body) ?? 'Server error ${res.statusCode}';
        print(res.statusCode);
        throw Exception(msg);
      } catch (_) {}
    }

    if (last != null) {
      final msg =
          _extractServerError(last.body) ?? 'Server error ${last.statusCode}';
      throw Exception(msg);
    }
    throw Exception('No reachable Update endpoint');
  }

  Future<void> _saveSection({required bool modifyImage}) async {
    if (_serverId == null) {
      _snack('Missing server Id');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final httpFileData = await _buildHttpFileData(
        customerId: _serverId!,
        httpFileId: _httpFileId ?? 0,
      );
      // If this isn't a profile image change, ensure IsModified=false
      if (!modifyImage) {
        httpFileData['IsModified'] = false;
        httpFileData['FileData'] = '';
        httpFileData['FileName'] = '';
        httpFileData['FileType'] = '';
      }

      final isModified = (httpFileData['IsModified'] as bool?) ?? false;
      final nextFileId = isModified ? 0 : (_fileId ?? 0);

      final dobIsoZ = _selectedDate != null
          ? DateTime(
              _selectedDate!.year,
              _selectedDate!.month,
              _selectedDate!.day,
              12,
            ).toUtc().toIso8601String()
          : null;

      await _putCustomerUpdate(
        id: _serverId!,
        name: _nameCtrl.text.trim(),
        surname: _surnameCtrl.text.trim(),
        phoneNumber: _phoneCtrl.text.trim(),
        emailId: _emailCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        gender: _gender ?? '',
        others: _othersCtrl.text.trim(),
        dobIsoZ: dobIsoZ,
        fileId: nextFileId,
        httpFileData: httpFileData,
      );

      // Refresh record
      await _fetchCustomerById(_serverId!);

      // Reset editing states for all sections
      setState(() {
        _editProfile = false;
        _editIdentity = false;
        _editContact = false;
        _editAddress = false;
        _editDates = false;
        _editOthers = false;
        _imageFile = null;
      });

      _snack('Saved');
    } catch (e) {
      _snack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ------------------------ Delete & Share ------------------------

  Future<void> _deleteCustomer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Customer"),
        content: const Text(
          "Are you sure you want to delete this customer from the server and locally?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (_serverId != null) {
      try {
        await _deleteOnServer(_serverId!);
        _snack('Customer deleted on server');
      } catch (e) {
        _snack('Server delete failed: $e');
      }
    }
    await _deleteLocalOnly();
  }

  Future<void> _deleteOnServer(int id) async {
    final token = await _resolveToken();
    final headers = <String, String>{
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    final candidates = <String>[
      '$_apiBaseWithApi/CustomerDataM/DeleteAsync/$id',
      '${_apiBaseUrl.trim().replaceAll(RegExp(r"/+$"), "")}/CustomerDataM/DeleteAsync/$id',
    ];

    http.Response? last;
    for (final url in candidates) {
      try {
        final res = await http.delete(Uri.parse(url), headers: headers);
        if (res.statusCode >= 200 && res.statusCode < 300) return;
        last = res;
        if (res.statusCode == 404) continue;
        final msg =
            _extractServerError(res.body) ?? 'Server error ${res.statusCode}';
        print(res.statusCode);
        throw Exception(msg);
      } catch (_) {}
    }
    if (last != null) {
      final msg =
          _extractServerError(last.body) ?? 'Server error ${last.statusCode}';
      throw Exception(msg);
    }
    throw Exception('No reachable Delete endpoint');
  }

  Future<void> _deleteLocalOnly() async {
    final prefs = await SharedPreferences.getInstance();
    final customersJson = prefs.getString('customers');
    if (customersJson != null) {
      List<dynamic> list = json.decode(customersJson);
      list.removeWhere((item) {
        final m = Map<String, dynamic>.from(item);
        final matchById =
            (m['serverId']?.toString() ?? '') == (_serverId?.toString() ?? '');
        final matchByFields =
            m['name'] == _customer.name &&
            m['surname'] == _customer.surname &&
            m['phone'] == _customer.phone;
        return matchById || matchByFields;
      });
      await prefs.setString('customers', json.encode(list));
      final lastUserJson = prefs.getString('last_user');
      if (lastUserJson != null) {
        final lastUser = json.decode(lastUserJson);
        final match =
            (lastUser['name'] == _customer.name &&
            lastUser['surname'] == _customer.surname &&
            lastUser['phone'] == _customer.phone);
        if (match) await prefs.remove('last_user');
      }
    }
    if (!mounted) return;
    _snack('Customer deleted locally');
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  Future<void> _shareCustomer() async {
    String safe(String? s) => (s ?? '').trim();
    final buf = StringBuffer()
      ..writeln('👤 ${safe(_nameCtrl.text)} ${safe(_surnameCtrl.text)}')
      ..writeln('📱 ${safe(_phoneCtrl.text)}')
      ..writeln('📧 ${safe(_emailCtrl.text)}')
      ..writeln('🏠 ${safe(_addressCtrl.text)}')
      ..writeln('🎂 ${safe(_dobCtrl.text)}')
      ..writeln('⚧️ ${safe(_gender)}');
    final othersText = _othersCtrl.text.trim();
    if (othersText.isNotEmpty) buf.writeln('📝 $othersText');
    await Share.share(buf.toString());
  }

  // ------------------------ Token & errors ------------------------

  Future<String?> _resolveToken() async {
    final dynamic t = TokenStorage.getToken();
    if (t is Future) return await t;
    return t as String?;
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

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ------------------------ UI ------------------------

  @override
  Widget build(BuildContext context) {
    final name = _nameCtrl.text;
    final surname = _surnameCtrl.text;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: kPrimaryBlue,
        toolbarHeight: 80,
        leading: const BackButton(color: Colors.white),
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white,
              child: _avatarBytes != null
                  ? ClipOval(
                      child: Image.memory(
                        _avatarBytes!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Text(
                      _initials(name, surname),
                      style: TextStyle(
                        color: kPrimaryBlue,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "${name} ${surname}".trim(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _phoneCtrl.text,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'share') _shareCustomer();
              if (val == 'delete') _deleteCustomer();
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'share', child: Text('Share Info')),
              PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                children: [
                  // Profile Image (no URL shown)
                  _cardWrapper(
                    title: 'Profile Image',
                    actions: _editProfile
                        ? [
                            IconButton(
                              tooltip: 'Save',
                              onPressed: _isSubmitting
                                  ? null
                                  : () => _saveSection(modifyImage: true),
                              icon: const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Cancel',
                              onPressed: _isSubmitting
                                  ? null
                                  : () {
                                      setState(() {
                                        _editProfile = false;
                                        _imageFile = null;
                                        if (_serverRecord != null)
                                          _applyServerRecord(_serverRecord!);
                                      });
                                    },
                              icon: const Icon(Icons.close, color: Colors.red),
                            ),
                          ]
                        : [
                            IconButton(
                              tooltip: 'Edit',
                              onPressed: () =>
                                  setState(() => _editProfile = true),
                              icon: const Icon(Icons.edit, color: Colors.black),
                            ),
                          ],
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () async {
                            if (_avatarBytes == null || _avatarBytes!.isEmpty) {
                              _snack('No image available');
                              return;
                            }
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => _ImageViewerScreen(
                                  bytes: _avatarBytes!,
                                  title:
                                      "${_nameCtrl.text} ${_surnameCtrl.text}",
                                ),
                              ),
                            );
                          },
                          child: Container(
                            height: 180,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.black12),
                            ),
                            child: _avatarBytes != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.memory(
                                      _avatarBytes!,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                    ),
                                  )
                                : Center(
                                    child: Icon(
                                      Icons.person,
                                      color: Colors.black38,
                                      size: 64,
                                    ),
                                  ),
                          ),
                        ),
                        if (_editProfile) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _pickImageFrom(ImageSource.camera),
                                  icon: const Icon(
                                    Icons.camera_alt_outlined,
                                    color: kPrimaryBlue,
                                  ),
                                  label: const Text(
                                    'Camera',
                                    style: TextStyle(color: kPrimaryBlue),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: kPrimaryBlue),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _pickImageFrom(ImageSource.gallery),
                                  icon: const Icon(
                                    Icons.photo_library_outlined,
                                    color: kPrimaryBlue,
                                  ),
                                  label: const Text(
                                    'Gallery',
                                    style: TextStyle(color: kPrimaryBlue),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: kPrimaryBlue),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),
                  // Name, Surname, Gender
                  _cardWrapper(
                    title: 'Name & Gender',
                    actions: _sectionActions(
                      editing: _editIdentity,
                      onEdit: () => setState(() => _editIdentity = true),
                      onCancel: () {
                        setState(() {
                          _editIdentity = false;
                          if (_serverRecord != null)
                            _applyServerRecord(_serverRecord!);
                        });
                      },
                      onSave: () => _saveSection(modifyImage: false),
                    ),
                    child: !_editIdentity
                        ? Column(
                            children: [
                              _rowLine('Name', _nameCtrl.text),
                              _rowLine('Surname', _surnameCtrl.text),
                              _rowLine('Gender', _gender ?? 'Not provided'),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _editField('Name', _nameCtrl),
                              _divider(),
                              _editField('Surname', _surnameCtrl),
                              _divider(),
                              const Text(
                                'Gender',
                                style: TextStyle(color: Colors.grey),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: ['Male', 'Female', 'Other'].map((g) {
                                  return Expanded(
                                    child: Row(
                                      children: [
                                        Radio<String>(
                                          value: g,
                                          groupValue: _gender,
                                          onChanged: (val) =>
                                              setState(() => _gender = val),
                                          activeColor: Colors.black87,
                                        ),
                                        Text(g),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                  ),

                  const SizedBox(height: 14),
                  // Contact
                  _cardWrapper(
                    title: 'Contact',
                    actions: _sectionActions(
                      editing: _editContact,
                      onEdit: () => setState(() => _editContact = true),
                      onCancel: () {
                        setState(() {
                          _editContact = false;
                          if (_serverRecord != null)
                            _applyServerRecord(_serverRecord!);
                        });
                      },
                      onSave: () => _saveSection(modifyImage: false),
                    ),
                    child: !_editContact
                        ? Column(
                            children: [
                              _rowLine('Phone', _phoneCtrl.text),
                              _rowLine('Email', _emailCtrl.text),
                            ],
                          )
                        : Column(
                            children: [
                              _editField('Phone', _phoneCtrl),
                              _divider(),
                              _editField('Email', _emailCtrl),
                            ],
                          ),
                  ),

                  const SizedBox(height: 14),
                  // Address
                  _cardWrapper(
                    title: 'Address',
                    actions: _sectionActions(
                      editing: _editAddress,
                      onEdit: () => setState(() => _editAddress = true),
                      onCancel: () {
                        setState(() {
                          _editAddress = false;
                          if (_serverRecord != null)
                            _applyServerRecord(_serverRecord!);
                        });
                      },
                      onSave: () => _saveSection(modifyImage: false),
                    ),
                    child: !_editAddress
                        ? _rowLine('Address', _addressCtrl.text)
                        : TextField(
                            controller: _addressCtrl,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              hintText: 'Address',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                  ),

                  const SizedBox(height: 14),
                  // Dates
                  _cardWrapper(
                    title: 'Dates',
                    actions: _sectionActions(
                      editing: _editDates,
                      onEdit: () => setState(() => _editDates = true),
                      onCancel: () {
                        setState(() {
                          _editDates = false;
                          if (_serverRecord != null)
                            _applyServerRecord(_serverRecord!);
                        });
                      },
                      onSave: () => _saveSection(modifyImage: false),
                    ),
                    child: !_editDates
                        ? Column(
                            children: [
                              _rowLine('DOB', _dobCtrl.text),
                              _rowLine('SDOB', _formatIsoToDdMmYyyy(_sdobIso)),
                            ],
                          )
                        : Column(
                            children: [
                              TextField(
                                controller: _dobCtrl,
                                readOnly: true,
                                onTap: _pickDate,
                                decoration: const InputDecoration(
                                  labelText: 'DOB',
                                  suffixIcon: Icon(Icons.calendar_today),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ],
                          ),
                  ),

                  const SizedBox(height: 14),
                  // Others
                  _cardWrapper(
                    title: 'Others',
                    actions: _sectionActions(
                      editing: _editOthers,
                      onEdit: () => setState(() => _editOthers = true),
                      onCancel: () {
                        setState(() {
                          _editOthers = false;
                          if (_serverRecord != null)
                            _applyServerRecord(_serverRecord!);
                        });
                      },
                      onSave: () => _saveSection(modifyImage: false),
                    ),
                    child: !_editOthers
                        ? _rowLine('Notes', _othersCtrl.text)
                        : TextField(
                            controller: _othersCtrl,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              hintText: 'Notes',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                  ),

                  const SizedBox(height: 14),
                ],
              ),
            ),
    );
  }

  // Card wrapper styled like your app
  Widget _cardWrapper({
    required String title,
    required Widget child,
    List<Widget>? actions,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(1, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
              const Spacer(),
              if (actions != null && actions.isNotEmpty) ...actions,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  List<Widget> _sectionActions({
    required bool editing,
    required VoidCallback onEdit,
    required VoidCallback onCancel,
    required VoidCallback onSave,
  }) {
    return editing
        ? [
            IconButton(
              tooltip: 'Save',
              onPressed: _isSubmitting ? null : onSave,
              icon: const Icon(Icons.check_circle, color: Colors.green),
            ),
            IconButton(
              tooltip: 'Cancel',
              onPressed: _isSubmitting ? null : onCancel,
              icon: const Icon(Icons.close, color: Colors.red),
            ),
          ]
        : [
            IconButton(
              tooltip: 'Edit',
              onPressed: onEdit,
              icon: const Icon(Icons.edit, color: Colors.black),
            ),
          ];
  }

  Widget _rowLine(String label, String value) {
    final safe = value.trim().isEmpty ? 'Not provided' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black54,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              safe,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editField(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _divider() => const SizedBox(height: 10);

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
        _dobCtrl.text = _fmt(picked);
      });
    }
  }

  String _formatIsoToDdMmYyyy(String? iso) {
    final d = _parseIso(iso);
    return d == null ? '' : _fmt(d);
  }
}

// ================== Server Document types & card ==================

class _ServerDoc {
  _ServerDoc({
    required this.id,
    required this.remarks,
    required this.fileName,
    required this.fileType,
    required this.url,
  });

  final String id;
  final String remarks;
  final String fileName;
  final String fileType; // may be mime or extension-ish
  final String? url; // absolute URL (not shown in UI)
}

class _ServerDocCard extends StatefulWidget {
  const _ServerDocCard({
    required this.doc,
    required this.isImage,
    required this.fetchBytes,
  });

  final _ServerDoc doc;
  final bool isImage;
  final Future<Uint8List?> Function(String url) fetchBytes;

  @override
  State<_ServerDocCard> createState() => _ServerDocCardState();
}

class _ServerDocCardState extends State<_ServerDocCard> {
  Uint8List? _imgBytes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.isImage && widget.doc.url != null) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    setState(() => _loading = true);
    final b = await widget.fetchBytes(widget.doc.url!);
    if (mounted) {
      setState(() {
        _imgBytes = b;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.doc.remarks.isNotEmpty
        ? widget.doc.remarks
        : (widget.doc.fileName.isNotEmpty ? widget.doc.fileName : 'Document');
    final isImg = widget.isImage && widget.doc.url != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(1, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row (remarks used as container name)
          Row(
            children: [
              const Icon(
                Icons.insert_drive_file_outlined,
                color: Colors.black54,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Preview (no URL text)
          if (isImg)
            GestureDetector(
              onTap: () async {
                if (_imgBytes == null && widget.doc.url != null)
                  await _loadImage();
                if (_imgBytes == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Preview not available')),
                  );
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        _ImageViewerScreen(bytes: _imgBytes!, title: title),
                  ),
                );
              },
              child: Container(
                height: 160,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black12),
                ),
                child: _loading
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : (_imgBytes != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                _imgBytes!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                              ),
                            )
                          : Center(
                              child: Text(
                                'Preview not available',
                                style: TextStyle(color: Colors.black54),
                              ),
                            )),
              ),
            )
          else
            Row(
              children: [
                Container(
                  height: 44,
                  width: 44,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: const Icon(Icons.description, color: Colors.black54),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.doc.fileName.isNotEmpty
                        ? widget.doc.fileName
                        : '(no file name)',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black87),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ================== Simple Image Viewer ==================

class _ImageViewerScreen extends StatelessWidget {
  const _ImageViewerScreen({required this.bytes, required this.title});
  final Uint8List bytes;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF38B6E4),
      ),
      backgroundColor: Colors.black,
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
