import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:docapp/api/api_constant.dart';
import 'package:docapp/model/customer.dart';
import 'package:docapp/storage/Token_storage.dart';
import 'package:docapp/utils/famildetailsutility.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;

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
  bool _sharingAll = false;

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
  final Set<String> _deletingDocIds = {}; // track deleting docs

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
            if (id != null) {
              setState(() =>
                  _serverId = (id is int) ? id : int.tryParse(id.toString()));
            }
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
            final idVal = e['Id'] ??
                e['ID'] ??
                e['CustomerId'] ??
                e['CustomerID'] ??
                e['id'];
            if (idVal != null) {
              foundId = idVal is int ? idVal : int.tryParse(idVal.toString());
            }
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
            final surname =
                (e['Surname'] ?? '').toString().trim().toLowerCase();
            if (name == first && surname == last) {
              final idVal = e['Id'] ??
                  e['ID'] ??
                  e['CustomerId'] ??
                  e['CustomerID'] ??
                  e['id'];
              if (idVal != null) {
                foundId =
                    idVal is int ? idVal : int.tryParse(idVal.toString());
              }
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

      // Fallback: if no docs in GET, try POST list
      if (_serverDocs.isEmpty) {
        final fromPost = await _fetchDocumentsViaPost(id);
        if (mounted && fromPost.isNotEmpty) {
          setState(() => _serverDocs = fromPost);
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _unwrapApi(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      final r = raw['Response'];
      if (r is Map<String, dynamic>) return r;
      if (r is List && r.isNotEmpty && r.first is Map) {
        return Map<String, dynamic>.from(r.first as Map);
      }
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
    if (g.startsWith('m')) {
      _gender = 'Male';
    } else if (g.startsWith('f')) {
      _gender = 'Female';
    } else if (g.isEmpty) {
      _gender = null;
    } else {
      _gender = 'Other';
    }

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
    _fileId =
        fileIdVal is int ? fileIdVal : int.tryParse((fileIdVal ?? '').toString());
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

    // Documents list from GET
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
          final urlStrRaw =
              (m['Url'] ?? m['url'] ?? fileName).toString();
          final urlStr =
              urlStrRaw.isNotEmpty ? _resolveFileUrl(urlStrRaw) : '';
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
    if (g.startsWith('m')) {
      _gender = 'Male';
    } else if (g.startsWith('f')) {
      _gender = 'Female';
    } else if (g.isEmpty) {
      _gender = null;
    } else {
      _gender = 'Other';
    }

    final dob = _parseLocalDob(c.dob);
    _selectedDate = dob;
    _dobCtrl.text = dob != null ? _fmt(dob) : '';
    _othersCtrl.text = '';
  }

  DateTime? _parseLocalDob(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    if (v.contains('-')) return DateTime.tryParse(v);
    final pz = v.split('/');
    if (pz.length == 3) {
      final d = int.tryParse(pz[0]) ?? 1;
      final m = int.tryParse(pz[1]) ?? 1;
      final y = int.tryParse(pz[2]) ?? 1970;
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
  }

  Future<Uint8List?> _fetchBytesWithAuth(String url) async {
    try {
      final token = await _resolveToken();
      final headers = <String, String>{'Accept': '*/*'};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
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

  // FIX: build HttpFileData with correct MIME and filename extension
  Future<Map<String, dynamic>> _buildHttpFileData({
    required int customerId,
    required int httpFileId,
  }) async {
    Uint8List? bytes;
    String fileName = "";
    String fileType = "image/jpeg"; // proper MIME

    if (_imageFile != null) {
      final compressed = await _compressImageFromFile(_imageFile!);
      if (compressed != null && compressed.isNotEmpty) {
        bytes = compressed;
        final base = p.basenameWithoutExtension(_imageFile!.path);
        fileName = "$base.jpg"; // ensure extension
      }
    }

    final isModified = bytes != null && bytes.isNotEmpty;
    final b64 = isModified ? base64Encode(bytes) : "";

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
      "ParentCustomerDataId": (_serverRecord?['ParentCustomerDataId'] ?? 0) as int,
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

  // ------------------------ Share All Documents (NEW) ------------------------

  String _inferMimeFromNameOrType(String name, String fileType) {
    final ext = p.extension(name).toLowerCase();
    if (ext == '.png') return 'image/png';
    if (ext == '.jpg' || ext == '.jpeg') return 'image/jpeg';
    if (ext == '.gif') return 'image/gif';
    if (ext == '.webp') return 'image/webp';
    if (ext == '.bmp') return 'image/bmp';
    if (ext == '.tif' || ext == '.tiff') return 'image/tiff';
    if (ext == '.pdf') return 'application/pdf';
    if (ext == '.csv') return 'text/csv';
    if (ext == '.xls') return 'application/vnd.ms-excel';
    if (ext == '.xlsx') {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (ext == '.doc') return 'application/msword';
    if (ext == '.docx') {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (ext == '.txt' || fileType.toLowerCase().contains('text')) {
      return 'text/plain';
    }

    // fallback from fileType if extension missing
    final t = fileType.toLowerCase();
    if (t.startsWith('image/')) return t;
    if (t.contains('pdf')) return 'application/pdf';
    if (t.contains('excel') || t.contains('sheet')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (t.contains('word')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    return 'application/octet-stream';
  }

  String _safeFileNameForDoc(_ServerDoc doc) {
    final base = doc.fileName.trim().isNotEmpty
        ? doc.fileName.trim()
        : 'document_${doc.id}';
    String ext = p.extension(base);
    if (ext.isEmpty) {
      final t = doc.fileType.toLowerCase();
      if (t.startsWith('image/')) {
        ext = '.${t.split('/').last}';
      } else if ((doc.url ?? '').isNotEmpty && doc.url!.contains('.')) {
        ext = p.extension(Uri.parse(doc.url!).path);
      } else {
        if (t.contains('pdf')) {
          ext = '.pdf';
        } else if (t.contains('excel') || t.contains('sheet')) ext = '.xlsx';
        else if (t.contains('word')) ext = '.docx';
        else if (t.contains('text')) ext = '.txt';
        else ext = '.bin';
      }
    }
    return base.endsWith(ext) ? base : '$base$ext';
  }

  Future<void> _shareAllDocuments() async {
    if (_serverDocs.isEmpty) {
      _snack('No documents to share');
      return;
    }

    setState(() => _sharingAll = true);
    try {
      final files = <XFile>[];
      final fallbackUrls = <String>[];

      for (final doc in _serverDocs) {
        if (doc.url == null || doc.url!.isEmpty) {
          if (doc.fileName.isNotEmpty) fallbackUrls.add(doc.fileName);
          continue;
        }
        try {
          final bytes = await _fetchBytesWithAuth(doc.url!);
          if (bytes != null && bytes.isNotEmpty) {
            final name = _safeFileNameForDoc(doc);
            final mime = _inferMimeFromNameOrType(name, doc.fileType);
            files.add(XFile.fromData(bytes, name: name, mimeType: mime));
          } else {
            fallbackUrls.add(doc.url!);
          }
        } catch (_) {
          fallbackUrls.add(doc.url!);
        }
      }

      final caption = StringBuffer();
      for (final d in _serverDocs) {
        final line = d.remarks.trim().isEmpty
            ? d.fileName
            : '${d.fileName} - ${d.remarks}';
        caption.writeln(line);
      }

      if (files.isNotEmpty) {
        if (fallbackUrls.isNotEmpty) {
          caption.writeln('\nLinks:');
          caption.writeln(fallbackUrls.join('\n'));
        }
        await Share.shareXFiles(files, text: caption.toString().trim());
      } else if (fallbackUrls.isNotEmpty) {
        await Share.share(('$caption\n${fallbackUrls.join('\n')}').trim());
      } else {
        _snack('Unable to gather any documents to share');
      }
    } finally {
      if (mounted) setState(() => _sharingAll = false);
    }
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

  // ------------------------ Documents: Delete support ------------------------

  Future<void> _deleteDocument(_ServerDoc doc) async {
    if (_serverId == null) {
      _snack('Missing server Id');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Document'),
        content: Text('Delete "${doc.fileName}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _deletingDocIds.add(doc.id));
    try {
      final ok = await _tryDeleteDocFromServer(doc);
      if (ok) {
        setState(() {
          _serverDocs.removeWhere((d) => d.id == doc.id);
        });
        _snack('Document deleted');
        // Optional: refresh to stay in sync with server
        if (_serverId != null) await _fetchCustomerById(_serverId!);
      } else {
        _snack('Delete failed');
      }
    } catch (e) {
      _snack('Delete failed: $e');
    } finally {
      if (mounted) setState(() => _deletingDocIds.remove(doc.id));
    }
  }

  Future<bool> _tryDeleteDocFromServer(_ServerDoc doc) async {
    final token = await _resolveToken();
    if (token == null || token.isEmpty) return false;

    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final idStr = doc.id.trim();
    final idInt = int.tryParse(idStr);

    // 1) Try DELETE endpoints
    final deleteCandidates = <String>[
      '$_apiBaseWithApi/CustomerDataM/FileRecordDeleteAsync/$idStr',
      '$_apiBaseWithApi/CustomerDataM/FileRecordDelete/$idStr',
      '$_apiBaseWithApi/CustomerDataM/FileRecordDeleteAsync?Id=$idStr',
      '$_apiBaseWithApi/CustomerDataM/FileRecordDelete?Id=$idStr',
      '${_apiBaseUrl.trim().replaceAll(RegExp(r"/+$"), "")}/CustomerDataM/FileRecordDeleteAsync/$idStr',
      '${_apiBaseUrl.trim().replaceAll(RegExp(r"/+$"), "")}/CustomerDataM/FileRecordDelete/$idStr',
    ];
    for (final url in deleteCandidates) {
      try {
        final res = await http.delete(Uri.parse(url), headers: headers);
        if (res.statusCode >= 200 && res.statusCode < 300) return true;
        if (res.statusCode == 404) continue; // try next
      } catch (_) {}
    }

    // 2) Try POST delete endpoint with body
    final postDeleteCandidates = <String>[
      '$_apiBaseWithApi/CustomerDataM/FileRecordDeleteAsync',
      '${_apiBaseUrl.trim().replaceAll(RegExp(r"/+$"), "")}/CustomerDataM/FileRecordDeleteAsync',
    ];
    for (final url in postDeleteCandidates) {
      try {
        final res = await http.post(
          Uri.parse(url),
          headers: {
            ...headers,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            "Id": idInt ?? idStr,
            "CustomerDataId": _serverId,
          }),
        );
        if (res.statusCode >= 200 && res.statusCode < 300) return true;
      } catch (_) {}
    }

    // 3) Try "mark as deleted" via Add endpoint (some APIs accept IsDeleted)
    final addEndpointCandidates = <String>[
      '$_apiBaseWithApi/CustomerDataM/FileRecordAddAsync',
      '${_apiBaseUrl.trim().replaceAll(RegExp(r"/+$"), "")}/CustomerDataM/FileRecordAddAsync',
    ];
    final addPayload = {
      "Id": idInt ?? 0,
      "IsModified": true,
      "FileData": "",
      "FileName": doc.fileName,
      "FileType": doc.fileType,
      "Remarks": doc.remarks,
      "IsDeleted": true,
      "CustomerDataId": _serverId,
    };
    for (final url in addEndpointCandidates) {
      try {
        final res = await http.post(
          Uri.parse(url),
          headers: {
            ...headers,
            'Content-Type': 'application/json',
          },
          body: jsonEncode(addPayload),
        );
        if (res.statusCode >= 200 && res.statusCode < 300) return true;
      } catch (_) {}
    }

    // 4) Fallback: soft delete via UpdateAsync with Documents = [IsDeleted:true]
    if (idInt != null) {
      final ok = await _deleteDocViaUpdate(idInt, doc);
      if (ok) return true;
    }

    return false;
  }

  Future<bool> _deleteDocViaUpdate(int docId, _ServerDoc doc) async {
    try {
      final token = await _resolveToken();
      if (token == null || token.isEmpty || _serverId == null) return false;

      final dobIsoZ = _selectedDate != null
          ? DateTime(
              _selectedDate!.year,
              _selectedDate!.month,
              _selectedDate!.day,
              12,
            ).toUtc().toIso8601String()
          : null;

      // Minimal HttpFileData unchanged
      final httpFileData = {
        "Id": _httpFileId ?? 0,
        "IsModified": false,
        "FileData": "",
        "FileName": "",
        "FileType": "",
        "Remarks": (_serverRecord?['HttpFileData']?['Remarks'] ?? '').toString(),
        "IsDeleted": false,
        "CustomerDataId": _serverId!,
      };

      final payload = <String, dynamic>{
        "Id": _serverId!,
        "ParentCustomerDataId": (_serverRecord?['ParentCustomerDataId'] ?? 0) as int,
        "Name": _nameCtrl.text.trim(),
        "Surname": _surnameCtrl.text.trim(),
        "PhoneNumber": _phoneCtrl.text.trim(),
        "FileId": _fileId ?? 0,
        "EmailId": _emailCtrl.text.trim(),
        "Address": _addressCtrl.text.trim(),
        "Gender": _gender ?? '',
        "Others": _othersCtrl.text.trim(),
        "ChildDatas": <dynamic>[],
        "HttpFileData": httpFileData,
        "Documents": [
          {
            "Id": docId,
            "IsModified": true,
            "FileData": "",
            "FileName": doc.fileName,
            "FileType": doc.fileType,
            "Remarks": doc.remarks,
            "IsDeleted": true,
            "CustomerDataId": _serverId!,
          }
        ],
      };
      if (dobIsoZ != null && dobIsoZ.isNotEmpty) {
        payload["DOB"] = dobIsoZ;
        payload["SDOB"] = dobIsoZ;
      }

      final headers = <String, String>{
        "Content-Type": "application/json; charset=utf-8",
        "Accept": "application/json",
        "Authorization": "Bearer $token",
      };

      final candidates = <String>[
        '$_apiBaseWithApi/CustomerDataM/UpdateAsync',
        '${_apiBaseUrl.trim().replaceAll(RegExp(r"/+$"), "")}/CustomerDataM/UpdateAsync',
      ];

      for (final url in candidates) {
        try {
          final res = await http.put(Uri.parse(url), headers: headers, body: jsonEncode(payload));
          if (res.statusCode >= 200 && res.statusCode < 300) return true;
        } catch (_) {}
      }
    } catch (_) {}
    return false;
  }

  // ------------------------ Documents section & POST fallback ------------------------

  Widget _documentsSection() {
    return _cardWrapper(
      title: 'Documents',
      actions: [
        if (_serverId != null)
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading
                ? null
                : () async {
                    await _fetchCustomerById(_serverId!);
                  },
            icon: const Icon(Icons.refresh, color: Colors.black),
          ),
        IconButton(
          tooltip: 'Share all',
          onPressed: (_serverDocs.isEmpty || _sharingAll) ? null : _shareAllDocuments,
          icon: _sharingAll
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.share, color: Colors.black),
        ),
      ],
      child: _serverDocs.isEmpty
          ? const Text('No documents found')
          : Column(
              children: [
                for (final doc in _serverDocs)
                  _ServerDocCard(
                    doc: doc,
                    isImage: _isImageUrlOrType(doc.fileType) ||
                        _isImageUrlOrType(doc.url) ||
                        _isImageUrlOrType(doc.fileName),
                    fetchBytes: _fetchBytesWithAuth,
                    onDelete: () => _deleteDocument(doc),
                    deleting: _deletingDocIds.contains(doc.id),
                  ),
              ],
            ),
    );
  }

  Future<List<_ServerDoc>> _fetchDocumentsViaPost(int customerId) async {
    try {
      final token = await _resolveToken();
      if (token == null || token.isEmpty) return [];

      final url = '$_apiBaseWithApi/CustomerDataM/FileRecordGetAsync';
      final res = await http.post(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          "CustomerDataId": customerId,
          "IncludeDeleted": false,
        }),
      );

      if (res.statusCode < 200 || res.statusCode >= 300) return [];

      final decoded = jsonDecode(res.body);
      final payload = _unwrapApi(decoded);

      List docs = const [];
      if (payload['Documents'] is List) {
        docs = payload['Documents'] as List;
      } else if (payload['documents'] is List) {
        docs = payload['documents'] as List;
      } else if (payload['Data'] is Map &&
          payload['Data']['Documents'] is List) {
        docs = payload['Data']['Documents'] as List;
      } else if (payload['Data'] is List) {
        docs = payload['Data'] as List;
      } else if (payload['Items'] is List) {
        docs = payload['Items'] as List;
      }

      final list = <_ServerDoc>[];
      for (final e in docs) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);

        final idStr = (m['Id'] ?? m['id'] ?? '').toString();
        final remarks = (m['Remarks'] ?? m['remarks'] ?? '').toString();
        final fileName = (m['FileName'] ?? m['fileName'] ?? '').toString();
        final fileType = (m['FileType'] ?? m['fileType'] ?? '').toString();
        final urlRaw = (m['Url'] ??
                m['url'] ??
                m['DocumentUrl'] ??
                m['DownloadUrl'] ??
                m['FileUrl'] ??
                m['FilePath'] ??
                fileName)
            .toString();
        final resolved = urlRaw.isNotEmpty ? _resolveFileUrl(urlRaw) : null;

        list.add(
          _ServerDoc(
            id: idStr.isEmpty
                ? DateTime.now().microsecondsSinceEpoch.toString()
                : idStr,
            remarks: remarks,
            fileName: fileName.isNotEmpty
                ? fileName
                : (urlRaw.isNotEmpty ? urlRaw : 'Document'),
            fileType: fileType,
            url: resolved,
          ),
        );
      }
      return list;
    } catch (_) {
      return [];
    }
  }

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
                      _initials(name,surname),
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
                  name.trim(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _surnameCtrl.text,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
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
                                        if (_serverRecord != null) {
                                          _applyServerRecord(_serverRecord!);
                                        }
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
                            if (_avatarBytes == null ||
                                _avatarBytes!.isEmpty) {
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
                                : const Center(
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
                                      customerImageProvider(ImageSource.gallery as Customer),
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
                          if (_serverRecord != null) {
                            _applyServerRecord(_serverRecord!);
                          }
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
                          if (_serverRecord != null) {
                            _applyServerRecord(_serverRecord!);
                          }
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
                          if (_serverRecord != null) {
                            _applyServerRecord(_serverRecord!);
                          }
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
                          if (_serverRecord != null) {
                            _applyServerRecord(_serverRecord!);
                          }
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
                          if (_serverRecord != null) {
                            _applyServerRecord(_serverRecord!);
                          }
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
                  // Documents list
                  _documentsSection(),

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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (actions != null) ...actions,
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
    if (!editing) {
      return [
        IconButton(
          tooltip: 'Edit',
          onPressed: _isSubmitting ? null : onEdit,
          icon: const Icon(Icons.edit, color: Colors.black),
        ),
      ];
    }
    return [
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
    ];
  }

  Widget _rowLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : '-',
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Divider(height: 1, color: Colors.black12),
    );
  }

  Widget _editField(String label, TextEditingController controller) {
    TextInputType? kt;
    if (label.toLowerCase() == 'phone') kt = TextInputType.phone;
    if (label.toLowerCase() == 'email') kt = TextInputType.emailAddress;
    return TextField(
      controller: controller,
      keyboardType: kt,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _selectedDate ??
        DateTime(now.year - 18, now.month, now.day); // default 18 years ago
    final first = DateTime(1900);
    final last = DateTime(now.year + 1, 12, 31);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dobCtrl.text = _fmt(picked);
      });
    }
  }

  String _formatIsoToDdMmYyyy(String? v) {
    final dt = _parseIso(v);
    return dt != null ? _fmt(dt) : '';
  }
}

// ================== Image Viewer ==================
class _ImageViewerScreen extends StatelessWidget {
  final Uint8List bytes;
  final String? title;
  const _ImageViewerScreen({required this.bytes, this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title?.trim().isNotEmpty == true ? title! : 'Image'),
        backgroundColor: const Color(0xFF38B6E4),
      ),
      backgroundColor: Colors.black,
      body: InteractiveViewer(
        minScale: 0.5,
        maxScale: 5,
        child: Center(
          child: Image.memory(bytes),
        ),
      ),
    );
  }
}

// ================== Server Document Model ==================
class _ServerDoc {
  final String id;
  final String remarks;
  final String fileName;
  final String fileType; // may be mime (image/png) or extension
  final String? url;

    const _ServerDoc({
    required this.id,
    required this.remarks,
    required this.fileName,
    required this.fileType,
    required this.url,
  });
}

// ================== Server Document Card (with Delete) ==================
class _ServerDocCard extends StatefulWidget {
  final _ServerDoc doc;
  final bool isImage;
  final Future<Uint8List?> Function(String url) fetchBytes;
  final VoidCallback? onDelete;
  final bool deleting;

  const _ServerDocCard({
    required this.doc,
    required this.isImage,
    required this.fetchBytes,
    this.onDelete,
    this.deleting = false,
  });

  @override
  State<_ServerDocCard> createState() => _ServerDocCardState();
}

class _ServerDocCardState extends State<_ServerDocCard> {
  Uint8List? _bytes;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.isImage && widget.doc.url != null && widget.doc.url!.isNotEmpty) {
      _loadBytes();
    }
  }

  Future<void> _loadBytes() async {
    if (_loading || widget.doc.url == null || widget.doc.url!.isEmpty) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final b = await widget.fetchBytes(widget.doc.url!);
      if (!mounted) return;
      setState(() {
        _bytes = b;
        _failed = b == null || b.isEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  IconData _iconForType() {
    final t = widget.doc.fileType.toLowerCase();
    final name = widget.doc.fileName.toLowerCase();
    final ext = p.extension(name.isNotEmpty ? name : t);
    if (t.startsWith('image/') ||
        ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.tif', '.tiff', '.heic'].contains(ext)) {
      return Icons.image_outlined;
    }
    if (t.contains('pdf') || ext == '.pdf') return Icons.picture_as_pdf_outlined;
    if (t.contains('sheet') || t.contains('excel') || ext == '.xls' || ext == '.xlsx' || ext == '.csv') {
      return Icons.grid_on_outlined;
    }
    if (t.contains('word') || ext == '.doc' || ext == '.docx' || ext == '.rtf') {
      return Icons.description_outlined;
    }
    if (t.contains('text') || ext == '.txt' || ext == '.log') {
      return Icons.notes_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  String _safeFileNameWithExt() {
    final base = widget.doc.fileName.trim().isNotEmpty
        ? widget.doc.fileName.trim()
        : 'document_${widget.doc.id}';
    String ext = p.extension(base);
    if (ext.isEmpty) {
      // Infer extension
      final t = widget.doc.fileType.toLowerCase();
      if (t.startsWith('image/')) {
        ext = '.${t.split('/').last}';
      } else if (widget.doc.url != null && widget.doc.url!.contains('.')) {
        ext = p.extension(Uri.parse(widget.doc.url!).path);
      } else {
        ext = widget.isImage ? '.jpg' : '.bin';
      }
    }
    if (!base.endsWith(ext)) return '$base$ext';
    return base;
  }

  String _inferMimeType(String name) {
    final ext = p.extension(name).toLowerCase();
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.bmp':
        return 'image/bmp';
      case '.tif':
      case '.tiff':
        return 'image/tiff';
      case '.pdf':
        return 'application/pdf';
      case '.csv':
        return 'text/csv';
      case '.xls':
        return 'application/vnd.ms-excel';
      case '.xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case '.doc':
        return 'application/msword';
      case '.docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case '.txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _openPreview(BuildContext context) async {
    if (widget.isImage) {
      if (_bytes == null || _bytes!.isEmpty) {
        await _loadBytes();
      }
      if (!mounted) return;
      if (_bytes == null || _bytes!.isEmpty) {
        _snack(context, 'Unable to load image');
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _ImageViewerScreen(
            bytes: _bytes!,
            title: widget.doc.fileName,
          ),
        ),
      );
      return;
    }
    // For non-image, share the URL (simple fallback)
    if (widget.doc.url != null && widget.doc.url!.isNotEmpty) {
      await Share.share(widget.doc.url!);
    } else {
      _snack(context, 'No preview available');
    }
  }

  Future<void> _shareDoc(BuildContext context) async {
    // If we have bytes (image), share directly; else share URL or meta text
    if (widget.isImage) {
      if (_bytes == null || _bytes!.isEmpty) {
        await _loadBytes();
      }
      if (!mounted) return;
      if (_bytes != null && _bytes!.isNotEmpty) {
        try {
          final name = _safeFileNameWithExt();
          final x = XFile.fromData(
            _bytes!,
            name: name,
            mimeType: _inferMimeType(name),
          );
          await Share.shareXFiles([x], text: widget.doc.remarks);
          return;
        } catch (_) {
          // fallthrough to share text
        }
      }
    }
    final text = StringBuffer()
      ..writeln(widget.doc.fileName)
      ..writeln(widget.doc.remarks);
    if (widget.doc.url != null && widget.doc.url!.isNotEmpty) {
      text.writeln(widget.doc.url!);
    }
    await Share.share(text.toString().trim());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Leading preview/icon
          SizedBox(
            width: 56,
            height: 56,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: widget.isImage
                  ? _imagePreview()
                  : Container(
                      color: Colors.grey.shade100,
                      child: Icon(_iconForType(), color: Colors.black54),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          // Title + remarks + actions
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.doc.fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                if (widget.doc.remarks.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.doc.remarks,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
                if (widget.doc.url != null && widget.doc.url!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.doc.url!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.blueGrey),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => _openPreview(context),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Open'),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _shareDoc(context),
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text('Share'),
                    ),
                    const Spacer(),
                    // Delete button on every doc
                    IconButton(
                      tooltip: 'Delete',
                      onPressed: widget.deleting ? null : widget.onDelete,
                      icon: widget.deleting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_forever, color: Colors.red),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagePreview() {
    if (_loading) {
      return Container(
        color: Colors.grey.shade100,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_failed || _bytes == null || _bytes!.isEmpty) {
      return Container(
        color: Colors.grey.shade100,
        child: const Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.black38),
        ),
      );
    }
    return Image.memory(
      _bytes!,
      fit: BoxFit.cover,
      width: 56,
      height: 56,
    );
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}