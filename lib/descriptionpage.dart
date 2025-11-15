import 'dart:convert';
import 'dart:io';

import 'package:docapp/api/api_constant.dart';
import 'package:docapp/api/description_api.dart'; // Must implement required methods
import 'package:docapp/model/customer.dart';
import 'package:docapp/storage/Token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // for Clipboard
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class DescriptionPage extends StatefulWidget {
  final Customer customer;
  const DescriptionPage({super.key, required this.customer});

  @override
  State<DescriptionPage> createState() => _DescriptionPageState();
}

class _DescriptionPageState extends State<DescriptionPage> {
  static const Color kPrimaryBlue = Color(0xFF38B6E4);

  // API
  late final CustomerApi _api;

  // Busy flags
  bool _isLoading = false;
  bool _isSubmitting = false;
  bool _sharingAll = false;

  // Controllers
  final _nameCtrl = TextEditingController();
  final _surnameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _registeredDobCtrl = TextEditingController();
  final _marriageDateCtrl = TextEditingController();
  final _othersCtrl = TextEditingController();

  // Gender
  String? _gender; // 'Male' | 'Female' | 'TransGender'

  // Dates
  DateTime? _selectedDOB;
  DateTime? _selectedRegisteredDOB;
  DateTime? _selectedMarriageDate;

  // Martial (API key name)
  String? _maritalStatus; // 'Single' | 'Married' | 'others'

  // Custom entries (local)
  List<Map<String, String>> _customEntries = [];

  // Image/profile
  final ImagePicker _picker = ImagePicker();
  File? _imageFile;
  Uint8List? _avatarBytes;
  String? _avatarUrl;
  int? _fileId;
  int? _httpFileId;

  // Server record + Documents
  Map<String, dynamic>? _serverRecord;
  List<_ServerDoc> _serverDocs = [];
  final Set<String> _deletingDocIds = {};

  // IDs
  int? _serverId;

  // Local model
  late Customer _customer;

  @override
  void initState() {
    super.initState();
    _api = CustomerApi(baseUrl: ApiConstants.baseUrl);
    _customer = widget.customer;
    _prefillFromLocal(_customer);
    _resolveServerIdThenFetch();
    _loadCustomEntries();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _surnameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _dobCtrl.dispose();
    _registeredDobCtrl.dispose();
    _marriageDateCtrl.dispose();
    _othersCtrl.dispose();
    super.dispose();
  }

  // ------------------------ Resolve & Fetch ------------------------
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
          if (name == _customer.name && surname == _customer.surname && phone == _customer.phone) {
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

  String _normPhone(String s) => s.replaceAll(RegExp(r'\D+'), '');

  Future<void> _loadServerIdFromList() async {
    try {
      final token = await _resolveToken();
      if (token == null || token.isEmpty) return;

      final list = await _api.getCustomers(token);
      int? foundId;
      final myPhone = _normPhone(_customer.phone);

      // Match by phone
      for (final e in list) {
        if (e is Map) {
          final ph = (e['PhoneNumber'] ?? '').toString();
          if (_normPhone(ph) == myPhone && myPhone.isNotEmpty) {
            final idVal = e['Id'] ?? e['ID'] ?? e['CustomerId'] ?? e['CustomerID'] ?? e['id'];
            if (idVal != null) foundId = idVal is int ? idVal : int.tryParse(idVal.toString());
            break;
          }
        }
      }
      // Fallback by name+surname
      if (foundId == null) {
        final first = _customer.name.trim().toLowerCase();
        final last = _customer.surname.trim().toLowerCase();
        for (final e in list) {
          if (e is Map) {
            final name = (e['Name'] ?? '').toString().trim().toLowerCase();
            final surname = (e['Surname'] ?? '').toString().trim().toLowerCase();
            if (name == first && surname == last) {
              final idVal = e['Id'] ?? e['ID'] ?? e['CustomerId'] ?? e['CustomerID'] ?? e['id'];
              if (idVal != null) foundId = idVal is int ? idVal : int.tryParse(idVal.toString());
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

      final record = await _api.getCustomerById(token, id);
      if (record.isEmpty) return;

      _applyServerRecord(record);
      await _upsertIdInCache(id);

      if (_serverDocs.isEmpty) {
        final fromPost = await _fetchDocumentsViaPost(id);
        if (mounted && fromPost.isNotEmpty) setState(() => _serverDocs = fromPost);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ------------------------ Apply server record ------------------------
  void _applyServerRecord(Map<String, dynamic> r) {
    _serverRecord = r;

    // Basic fields
    _nameCtrl.text = (r['Name'] ?? '').toString();
    _surnameCtrl.text = (r['Surname'] ?? '').toString();
    _phoneCtrl.text = (r['PhoneNumber'] ?? '').toString();
    _emailCtrl.text = (r['EmailId'] ?? '').toString();
    _addressCtrl.text = (r['Address'] ?? '').toString();
    _othersCtrl.text = (r['Others'] ?? '').toString();

    // Gender
    final g = (r['Gender'] ?? '').toString().trim().toLowerCase();
    if (g.startsWith('m')) {
      _gender = 'Male';
    } else if (g.startsWith('f')) _gender = 'Female';
    else if (g.isEmpty) _gender = null;
    else _gender = 'TransGender';

    // Dates
    final dobIso = (r['DOB'] ?? '').toString();
    _selectedDOB = _tryParseIso(dobIso);
    _dobCtrl.text = _selectedDOB != null ? _fmt(_selectedDOB!) : '';

    final sdobIso = (r['SDOB'] ?? '').toString();
    _selectedRegisteredDOB = _tryParseIso(sdobIso);
    _registeredDobCtrl.text = _selectedRegisteredDOB != null ? _fmt(_selectedRegisteredDOB!) : '';

    // Martial/Marital and MarriedDate
    final ms = (r['MartialStatus'] ?? r['MaritalStatus'] ?? '').toString();
    _maritalStatus = ms.isEmpty ? null : ms;

    final marriedIso = (r['MarriedDate'] ?? r['MarriageDate'] ?? '').toString();
    _selectedMarriageDate = _tryParseIso(marriedIso);
    _marriageDateCtrl.text = _selectedMarriageDate != null ? _fmt(_selectedMarriageDate!) : '';

    // File info
    final fileIdVal = r['FileId'];
    final httpFileData = r['HttpFileData'];
    final httpFileIdVal = (httpFileData is Map) ? httpFileData['Id'] : null;
    _fileId = fileIdVal is int ? fileIdVal : int.tryParse((fileIdVal ?? '').toString());
    _httpFileId = httpFileIdVal is int ? httpFileIdVal : int.tryParse((httpFileIdVal ?? '').toString());

    // Profile image URL
    String fn = '';
    bool isDeleted = false;
    if (httpFileData is Map) {
      fn = (httpFileData['FileName'] ?? '').toString();
      isDeleted = (httpFileData['IsDeleted'] ?? false) == true;
    }
    _avatarUrl = (fn.isNotEmpty && !isDeleted) ? _resolveFileUrl(fn) : null;

    if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      _fetchBytesWithAuth(_avatarUrl!).then((b) {
        if (!mounted) return;
        if (b != null && b.isNotEmpty) setState(() => _avatarBytes = b);
      });
    }

    // Documents (skip deleted)
    _serverDocs = [];
    final docs = r['Documents'];
    if (docs is List) {
      for (final e in docs) {
        if (e is Map) {
          final m = Map<String, dynamic>.from(e);
          if (_docIsDeleted(m)) continue;
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

  // ------------------------ Prefill local ------------------------
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
    } else if (g.startsWith('f')) _gender = 'Female';
    else if (g.isEmpty) _gender = null;
    else _gender = 'TransGender';

    final dob = _parseLocalDate(c.dob);
    _selectedDOB = dob;
    _dobCtrl.text = dob != null ? _fmt(dob) : '';

    final rd = _parseLocalDate(c.dob);
    _selectedRegisteredDOB = rd;
    _registeredDobCtrl.text = rd != null ? _fmt(rd) : '';

    _othersCtrl.text = '';
  }

  // ------------------------ Utils ------------------------
  Future<String?> _resolveToken() async {
    final dynamic t = TokenStorage.getToken();
    if (t is Future) return await t;
    return t as String?;
  }

  DateTime? _tryParseIso(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    try {
      return DateTime.tryParse(v);
    } catch (_) {
      return null;
    }
  }

  DateTime? _parseLocalDate(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final s = v.trim();
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    if (s.contains('/')) {
      final parts = s.split('/');
      if (parts.length == 3) {
        final d = int.tryParse(parts[0]) ?? 1;
        final m = int.tryParse(parts[1]) ?? 1;
        final y = int.tryParse(parts[2]) ?? 1970;
        return DateTime(y, m, d);
      }
    }
    return null;
  }

  String _fmt(DateTime dt) => "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}";

  String _resolveFileUrl(String fileNameOrUrl) {
    if (fileNameOrUrl.isEmpty) return fileNameOrUrl;
    final u = fileNameOrUrl.trim();
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    if (u.startsWith('/')) return '${_api.baseWithoutApi}$u';
    return '${_api.baseWithoutApi}/$u';
  }

  Future<Uint8List?> _fetchBytesWithAuth(String url) async {
    final token = await _resolveToken();
    return _api.fetchBytesWithAuth(token, url);
  }

  // Robust bool and doc deletion check
  bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes';
    }
    return false;
  }

  bool _docIsDeleted(Map<String, dynamic> m) {
    final v = m['isDelete'] ?? m['IsDelete'] ?? m['IsDeleted'] ?? m['isDeleted'];
    return _toBool(v);
  }

  // ------------------------ Pickers ------------------------
  Future<void> _pickDOB() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDOB ?? now,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _selectedDOB = picked;
        _dobCtrl.text = _fmt(picked);
      });
    }
  }

  Future<void> _pickRegisteredDOB() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedRegisteredDOB ?? now,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _selectedRegisteredDOB = picked;
        _registeredDobCtrl.text = _fmt(picked);
      });
    }
  }

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
        _marriageDateCtrl.text = _fmt(picked);
      });
    }
  }

  // Alias if some code references registerdob()
  String? registerdob() => _isoUtcNoon(_selectedRegisteredDOB);

  // ------------------------ Custom entries (local store) ------------------------
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

  Future<void> _showAddCustomEntryDialog() async {
    final typeController = TextEditingController();
    final detailController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Add Custom Entry"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: typeController, decoration: const InputDecoration(labelText: "Type")),
            TextField(controller: detailController, decoration: const InputDecoration(labelText: "Detail")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Add")),
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
  }

  // ------------------------ Image pick/compress ------------------------
  Future<void> _pickImageFrom(ImageSource src) async {
    final picked = await _picker.pickImage(source: src);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _imageFile = File(picked.path);
      _avatarBytes = bytes;
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
    const fileType = "image/jpeg";

    if (_imageFile != null) {
      final compressed = await _compressImageFromFile(_imageFile!);
      if (compressed != null && compressed.isNotEmpty) {
        bytes = compressed;
        final base = p.basenameWithoutExtension(_imageFile!.path);
        fileName = "$base.jpg";
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
      "IsDelete": false,
      "CustomerDataId": customerId,
    };
  }

  // ------------------------ Save (exact keys; Z timestamps) ------------------------
  String? _isoUtcNoon(DateTime? d) {
    if (d == null) return null;
    final localNoon = DateTime(d.year, d.month, d.day, 12, 0, 0);
    return localNoon.toUtc().toIso8601String();
  }

  Future<void> _saveAll() async {
    if (_nameCtrl.text.trim().isEmpty) {
      _snack('Name is required');
      return;
    }
    if (_phoneCtrl.text.trim().isEmpty) {
      _snack('Phone No is required');
      return;
    }
    if ((_maritalStatus ?? '').toLowerCase() == 'married' &&
        _marriageDateCtrl.text.trim().isEmpty) {
      _snack('Please select marriage date.');
      return;
    }
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
      final isModified = (httpFileData['IsModified'] as bool?) ?? false;
      final nextFileId = isModified ? 0 : (_fileId ?? 0);

      // ISO with Z (noon anchor)
      final dobZ = _isoUtcNoon(_selectedDOB);
      final sdobZ = _isoUtcNoon(_selectedRegisteredDOB) ?? dobZ;
      final marriedZ = _isoUtcNoon(_selectedMarriageDate);

      final payload = <String, dynamic>{
        "Id": _serverId!,                        // required for update
        "Name": _nameCtrl.text.trim(),
        "Surname": _surnameCtrl.text.trim(),
        "PhoneNumber": _phoneCtrl.text.trim(),
        "FileId": nextFileId,
        "EmailId": _emailCtrl.text.trim(),
        "Address": _addressCtrl.text.trim(),
        "Gender": (_gender ?? '').toLowerCase(), // consistent with Add page
        "Others": _othersCtrl.text.trim(),

        // exact keys with Z timestamps
        if (dobZ != null)  "DOB": dobZ,
        if (sdobZ != null) "SDOB": sdobZ,
        "MartialStatus": _maritalStatus ?? "",
        "MarriedDate": (_maritalStatus?.toLowerCase() == 'married') ? (marriedZ ?? sdobZ ?? dobZ) : null,

        // image
        "HttpFileData": httpFileData,

        // optional
        "ChildDatas": <dynamic>[],
        "Documents": isModified ? [Map<String, dynamic>.from(httpFileData)] : <dynamic>[],
      };

      final token = await _resolveToken();
      if (token == null || token.isEmpty) throw Exception('No token');

      await _api.updateCustomer(token, payload);
      await _fetchCustomerById(_serverId!);

      _imageFile = null;
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
        content: const Text("Are you sure you want to delete this customer from the server and locally?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;

    if (_serverId != null) {
      try {
        final ok = await _deleteCustomerOnServer(_serverId!);
        if (ok) _snack('Customer deleted on server');
      } catch (e) {
        _snack('Server delete failed: $e');
      }
    }
    await _deleteLocalOnly();
  }

  Future<bool> _deleteCustomerOnServer(int id) async {
    final token = await _resolveToken();
    if (token == null || token.isEmpty) return false;

    final url = '${_api.baseWithoutApi}/api/CustomerDataM/DeleteAsync/$id';
    final res = await http.delete(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  Future<void> _deleteLocalOnly() async {
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

  // ------------------------ Documents & sharing ------------------------
  Widget _documentsSection() {
    return _cardWrapper(
      title: 'Documents',
      actions: [
        if (_serverId != null)
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : () async {
              await _fetchCustomerById(_serverId!);
            },
            icon: const Icon(Icons.refresh, color: Colors.black),
          ),
        IconButton(
          tooltip: 'Share all',
          onPressed: (_serverDocs.isEmpty || _sharingAll) ? null : _shareAllDocuments,
          icon: _sharingAll
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.share, color: Colors.black),
        ),
      ],
      child: _serverDocs.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('No documents found', style: TextStyle(color: Colors.black54)),
            )
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
                    // NEW:
                    onEdit: () => _editDocument(doc),
                    onInfo: () => _showDocDetails(doc),
                  ),
              ],
            ),
    );
  }

  Future<List<_ServerDoc>> _fetchDocumentsViaPost(int customerId) async {
    try {
      final token = await _resolveToken();
      if (token == null || token.isEmpty) return [];

      final maps = await _api.getDocumentsViaPost(token, customerId);
      final list = <_ServerDoc>[];
      for (final m0 in maps) {
        final m = Map<String, dynamic>.from(m0);
        if (_docIsDeleted(m)) continue;

        final idStr = (m['Id'] ?? m['id'] ?? '').toString();
        final remarks = (m['Remarks'] ?? m['remarks'] ?? '').toString();
        final fileName = (m['FileName'] ?? m['fileName'] ?? '').toString();
        final fileType = (m['FileType'] ?? m['fileType'] ?? '').toString();
        final urlRaw = (m['Url'] ?? m['url'] ?? m['DocumentUrl'] ?? m['DownloadUrl'] ?? m['FileUrl'] ?? m['FilePath'] ?? fileName).toString();
        final resolved = urlRaw.isNotEmpty ? _resolveFileUrl(urlRaw) : null;

        list.add(_ServerDoc(
          id: idStr.isEmpty ? DateTime.now().microsecondsSinceEpoch.toString() : idStr,
          remarks: remarks,
          fileName: fileName.isNotEmpty ? fileName : (urlRaw.isNotEmpty ? urlRaw : 'Document'),
          fileType: fileType,
          url: resolved,
        ));
      }
      return list;
    } catch (_) {
      return [];
    }
  }

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
      final ok = await _deleteDocByFileRecordUpdate(doc);
      if (ok) {
        setState(() {
          _serverDocs.removeWhere((d) => d.id == doc.id);
        });
        if (_serverId != null) await _fetchCustomerById(_serverId!);
        _snack('Document deleted');
      } else {
        _snack('Delete failed');
      }
    } catch (e) {
      _snack('Delete failed: $e');
    } finally {
      if (mounted) setState(() => _deletingDocIds.remove(doc.id));
    }
  }

  Future<bool> _deleteDocByFileRecordUpdate(_ServerDoc doc) async {
    final token = await _resolveToken();
    if (token == null || token.isEmpty || _serverId == null) return false;

    final url = '${_api.baseWithoutApi}/api/CustomerDataM/FileRecordUpdateAsync';
    final idInt = int.tryParse(doc.id);
    final payload = {
      "Id": idInt ?? 0,
      "CustomerDataId": _serverId,
      "IsModified": true,
      "IsDeleted": true,
      "IsDelete": true,
      "Remarks": doc.remarks,
      "FileName": doc.fileName,
      "FileType": doc.fileType,
      "FileData": "",
    };

    try {
      final res = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
        },
        body: jsonEncode(payload),
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  // ------------------------ Rename + Details ------------------------
  Future<void> _editDocument(_ServerDoc doc) async {
    final nameCtrl = TextEditingController(text: doc.fileName);
    final remarksCtrl = TextEditingController(text: doc.remarks);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Document'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'File name'),
            ),
            TextField(
              controller: remarksCtrl,
              decoration: const InputDecoration(labelText: 'Remarks (optional)'),
            ),
            const SizedBox(height: 8),
            Text(
              'Tip: include extension (.pdf, .jpg) to keep type consistent',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );

    if (saved != true) return;
    final newName = nameCtrl.text.trim();
    final newRemarks = remarksCtrl.text.trim();

    if (newName.isEmpty) {
      _snack('File name cannot be empty');
      return;
    }

    final ok = await _updateDocumentMeta(doc, fileName: newName, remarks: newRemarks);
    if (ok) {
      setState(() {
        final idx = _serverDocs.indexWhere((d) => d.id == doc.id);
        if (idx != -1) {
          final newType = _inferMimeFromNameOrType(newName, doc.fileType);
          _serverDocs[idx] = _ServerDoc(
            id: doc.id,
            fileName: newName,
            remarks: newRemarks,
            fileType: newType,
            url: doc.url,
          );
        }
      });
      _snack('Document updated');
    } else {
      _snack('Update failed');
    }
  }

  Future<bool> _updateDocumentMeta(_ServerDoc doc, {required String fileName, String? remarks}) async {
    final token = await _resolveToken();
    if (token == null || token.isEmpty || _serverId == null) return false;

    final url = '${_api.baseWithoutApi}/api/CustomerDataM/FileRecordUpdateAsync';
    final idInt = int.tryParse(doc.id) ?? 0;
    final newType = _inferMimeFromNameOrType(fileName, doc.fileType);

    final payload = {
      "Id": idInt,
      "CustomerDataId": _serverId,
      "IsModified": true,
      "IsDeleted": false,
      "IsDelete": false,
      "Remarks": (remarks ?? doc.remarks),
      "FileName": fileName,
      "FileType": newType,
      "FileData": "", // metadata-only update
    };

    try {
      final res = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
        },
        body: jsonEncode(payload),
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<void> _showDocDetails(_ServerDoc doc) async {
    int? sizeBytes;
    if ((doc.url ?? '').isNotEmpty) {
      try {
        sizeBytes = await _getContentLength(doc.url!);
      } catch (_) {}
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Document Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              _kvRow('Name', doc.fileName),
              _kvRow('Type', doc.fileType.isNotEmpty ? doc.fileType : '—'),
              _kvRow('ID', doc.id),
              if (doc.remarks.trim().isNotEmpty) _kvRow('Remarks', doc.remarks),
              if ((doc.url ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: doc.url!));
                    Navigator.pop(ctx);
                    _snack('Link copied');
                  },
                  child: _kvRow('URL', doc.url!, valueColor: Colors.blueGrey),
                ),
              ],
              const SizedBox(height: 6),
              _kvRow('Size', sizeBytes != null ? _formatBytes(sizeBytes) : 'Unknown'),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _editDocument(doc);
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Rename'),
                  ),
                  const SizedBox(width: 8),
                  if ((doc.url ?? '').isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: doc.url!));
                        Navigator.pop(ctx);
                        _snack('Link copied');
                      },
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('Copy link'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kvRow(String k, String v, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(v, style: TextStyle(color: valueColor ?? Colors.black87))),
        ],
      ),
    );
  }

  Future<int?> _getContentLength(String url) async {
    final token = await _resolveToken();
    try {
      final headers = <String, String>{'Accept': '*/*'};
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';

      // Try HEAD first
      final head = await http.head(Uri.parse(url), headers: headers);
      final cl = head.headers['content-length'];
      if (cl != null) {
        final n = int.tryParse(cl);
        if (n != null && n > 0) return n;
      }

      // Fallback: range request for quick size
      final rangeHeaders = Map<String, String>.from(headers)..['Range'] = 'bytes=0-0';
      final get = await http.get(Uri.parse(url), headers: rangeHeaders);
      final cr = get.headers['content-range']; // e.g., bytes 0-0/12345
      if (cr != null && cr.contains('/')) {
        final total = cr.split('/').last.trim();
        final n = int.tryParse(total);
        if (n != null && n > 0) return n;
      }
    } catch (_) {}
    return null;
  }

  bool _isImageUrlOrType(String? mimeOrUrl) {
    if (mimeOrUrl == null) return false;
    final s = mimeOrUrl.toLowerCase();
    if (s.startsWith('image/')) return true;
    final ext = p.extension(s);
    return ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.tif', '.tiff', '.heic'].contains(ext);
  }

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
    if (ext == '.xlsx') return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    if (ext == '.doc') return 'application/msword';
    if (ext == '.docx') return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    if (ext == '.txt') return 'text/plain';
    final t = fileType.toLowerCase();
    if (t.startsWith('image/')) return t;
    if (t.contains('pdf')) return 'application/pdf';
    if (t.contains('excel') || t.contains('sheet')) return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    if (t.contains('word')) return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    if (t.contains('text')) return 'text/plain';
    return 'application/octet-stream';
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 2)} ${units[unit]}';
  }

  // ------------------------ Share all docs ------------------------
  Future<void> _shareAllDocuments() async {
    if (_serverDocs.isEmpty) {
      _snack('No documents to share');
      return;
    }

    setState(() => _sharingAll = true);
    try {
      final files = <XFile>[];
      final fallbackUrls = <String>[];
      final token = await _resolveToken();

      for (final doc in _serverDocs) {
        if (doc.url == null || doc.url!.isEmpty) {
          if (doc.fileName.isNotEmpty) fallbackUrls.add(doc.fileName);
          continue;
        }
        try {
          final bytes = await _api.fetchBytesWithAuth(token, doc.url!);
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
        final line = d.remarks.trim().isEmpty ? d.fileName : '${d.fileName} - ${d.remarks}';
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

  String _safeFileNameForDoc(_ServerDoc doc) {
    final base = doc.fileName.trim().isNotEmpty ? doc.fileName.trim() : 'document_${doc.id}';
    String ext = p.extension(base);
    if (ext.isEmpty) {
      final t = doc.fileType.toLowerCase();
      if (t.startsWith('image/')) {
        ext = '.${t.split('/').last}';
      } else if ((doc.url ?? '').isNotEmpty && doc.url!.contains('.')) {
        ext = p.extension(Uri.parse(doc.url!).path);
      } else {
        ext = '.bin';
      }
    }
    return base.endsWith(ext) ? base : '$base$ext';
  }

  // ------------------------ UI helpers ------------------------
  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey, fontSize: 16),
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12), // a tiny bit tighter
      border: InputBorder.none,
    );
  }

  Widget _cardWrapper({
    required String title,
    required Widget child,
    List<Widget>? actions,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
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
          Row(children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
              ),
            ),
            if (actions != null) ...actions,
          ]),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _genderChips() {
    final items = ['Male', 'Female', 'TransGender'];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final g in items)
          ChoiceChip(
            label: Text(g),
            selected: _gender == g,
            onSelected: (v) => setState(() => _gender = g),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  Widget _maritalChips() {
    final items = ['Single', 'Married', 'others'];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final s in items)
          ChoiceChip(
            label: Text(s),
            selected: _maritalStatus == s,
            onSelected: (v) {
              setState(() {
                _maritalStatus = s;
                if (s != 'Married') {
                  _selectedMarriageDate = null;
                  _marriageDateCtrl.clear();
                }
              });
            },
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  // ------------------------ Build ------------------------
  @override
  Widget build(BuildContext context) {
    final name = _nameCtrl.text;
    final surname = _surnameCtrl.text;

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        elevation: 0,
        toolbarHeight: 60,
        backgroundColor: const Color.fromARGB(0, 255, 254, 254),
        leading: const BackButton(color: Colors.white),
        foregroundColor: Colors.white,
        actionsIconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          "Edit Customer",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
              PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
            ],
          ),
        ],
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage("assets/images/Background2.jpeg"),
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),

      // Scrollable content
      body: _isLoading
          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                children: [
                  // Profile Image
                  _cardWrapper(
                    title: 'Profile Image',
                    actions: [
                      IconButton(
                        tooltip: 'View',
                        onPressed: () {
                          if (_avatarBytes == null || _avatarBytes!.isEmpty) {
                            _snack('No image available');
                            return;
                          }
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => _ImageViewerScreen(
                                bytes: _avatarBytes!,
                                title: "$name $surname",
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.open_in_new, color: Colors.black),
                      ),
                    ],
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () async {
                            final src = await showModalBottomSheet<ImageSource>(
                              context: context,
                              showDragHandle: true,
                              builder: (ctx) => SafeArea(
                                child: Wrap(
                                  children: [
                                    ListTile(
                                      leading: const Icon(Icons.camera_alt_outlined),
                                      title: const Text('Camera'),
                                      onTap: () => Navigator.pop(ctx, ImageSource.camera),
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.photo_library_outlined),
                                      title: const Text('Gallery'),
                                      onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                                    ),
                                  ],
                                ),
                              ),
                            );
                            if (src != null) await _pickImageFrom(src);
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
                                    child: Image.memory(_avatarBytes!, fit: BoxFit.cover),
                                  )
                                : const Center(child: Icon(Icons.person, color: Colors.black38, size: 64)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Name & Gender
                  _cardWrapper(
                    title: 'Name & Gender',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(controller: _surnameCtrl, decoration: _inputDecoration("Surname")),
                        const Divider(color: Colors.black12),
                        TextField(controller: _nameCtrl, decoration: _inputDecoration("Name")),
                        const Divider(color: Colors.black12),
                        const SizedBox(height: 2),
                        const Text("Gender", style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 6),
                        _genderChips(), // responsive, no overflow
                      ],
                    ),
                  ),

                  // Dates
                  _cardWrapper(
                    title: 'Dates',
                    child: Column(
                      children: [
                        TextField(
                          controller: _dobCtrl,
                          readOnly: true,
                          onTap: _pickDOB,
                          decoration: _inputDecoration("Date of Birth").copyWith(
                            suffixIcon: const Icon(Icons.calendar_today, color: Colors.black54, size: 20),
                          ),
                        ),
                        const Divider(color: Colors.black12),
                        TextField(
                          controller: _registeredDobCtrl,
                          readOnly: true,
                          onTap: _pickRegisteredDOB,
                          decoration: _inputDecoration("Registered Date of Birth").copyWith(
                            suffixIcon: const Icon(Icons.calendar_today, color: Colors.black54, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Contact
                  _cardWrapper(
                    title: 'Contact',
                    child: Column(
                      children: [
                        TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone, decoration: _inputDecoration("Phone No")),
                        const Divider(color: Colors.black12),
                        TextField(controller: _emailCtrl, decoration: _inputDecoration("Email")),
                      ],
                    ),
                  ),

                  // Address
                  _cardWrapper(
                    title: 'Address',
                    child: TextField(controller: _addressCtrl, decoration: _inputDecoration("Address")),
                  ),

                  // Marital Status
                  _cardWrapper(
                    title: 'Marital Status',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _maritalChips(),
                        if (_maritalStatus == 'Married') ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: _marriageDateCtrl,
                            readOnly: true,
                            onTap: _pickMarriageDate,
                            decoration: _inputDecoration("Marriage Date").copyWith(
                              suffixIcon: const Icon(Icons.calendar_today, color: Colors.black54, size: 20),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Others + Custom entries
                  _cardWrapper(
                    title: 'Others',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _othersCtrl,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'Notes',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _showAddCustomEntryDialog,
                                icon: const Icon(Icons.add, color: kPrimaryBlue, size: 20),
                                label: const Text("Add Custom Entry", style: TextStyle(color: kPrimaryBlue)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: kPrimaryBlue),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_customEntries.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: _customEntries.map((entry) {
                              return Chip(
                                label: Text("${entry['type']}: ${entry['detail']}"),
                                backgroundColor: Colors.grey.shade200,
                                deleteIcon: const Icon(Icons.close, size: 16),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                onDeleted: () async {
                                  setState(() => _customEntries.remove(entry));
                                  await _saveCustomEntries();
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Documents (will show even if empty with a placeholder)
                  _documentsSection(),

                  // Spacer so content doesn't go under bottom button
                  const SizedBox(height: 80),
                ],
              ),
            ),

      // Bottom Save button (fixed, smaller padding/spacing)
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _saveAll,
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryBlue,
              foregroundColor: Colors.white,
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 14), // tighter
            ),
            child: _isSubmitting
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      SizedBox(width: 6),
                      Text("Saving...", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  )
                : const Text("Save Changes", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
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
      appBar: AppBar(title: Text(title?.trim().isNotEmpty == true ? title! : 'Image'), backgroundColor: const Color(0xFF38B6E4)),
      backgroundColor: Colors.black,
      body: InteractiveViewer(minScale: 0.5, maxScale: 5, child: Center(child: Image.memory(bytes))),
    );
  }
}

// ================== Server Document Model ==================
class _ServerDoc {
  final String id;
  final String remarks;
  final String fileName;
  final String fileType;
  final String? url;

  const _ServerDoc({
    required this.id,
    required this.remarks,
    required this.fileName,
    required this.fileType,
    required this.url,
  });
}

// ================== Server Document Card ==================
class _ServerDocCard extends StatefulWidget {
  final _ServerDoc doc;
  final bool isImage;
  final Future<Uint8List?> Function(String url) fetchBytes;
  final VoidCallback? onDelete;
  final bool deleting;

  // NEW
  final VoidCallback? onEdit;
  final VoidCallback? onInfo;

  const _ServerDocCard({
    required this.doc,
    required this.isImage,
    required this.fetchBytes,
    this.onDelete,
    this.deleting = false,
    this.onEdit,
    this.onInfo,
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
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87),
                ),
                if (widget.doc.remarks.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(widget.doc.remarks, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54)),
                ],
                if (widget.doc.url != null && widget.doc.url!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(widget.doc.url!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.blueGrey)),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => _openPreview(context),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Open'),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _shareDoc(context),
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text('Share'),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    ),

                    // IconButton(
                    //   tooltip: 'Details',
                    //   onPressed: widget.deleting ? null : widget.onInfo,
                    //   icon: const Icon(Icons.info_outline, color: Colors.black87),
                      
                    // ),
                    // IconButton(
                    //   tooltip: 'Rename',
                    //   onPressed: widget.deleting ? null : widget.onEdit,
                    //   icon: const Icon(Icons.edit_outlined, color: Colors.black87),
                    // ),

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
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (_failed || _bytes == null || _bytes!.isEmpty) {
      return Container(
        color: Colors.grey.shade100,
        child: const Center(child: Icon(Icons.broken_image_outlined, color: Colors.black38)),
      );
    }
    return Image.memory(_bytes!, fit: BoxFit.cover, width: 56, height: 56);
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
    if (widget.doc.url != null && widget.doc.url!.isNotEmpty) {
      await Share.share(widget.doc.url!);
    } else {
      _snack(context, 'No preview available');
    }
  }

  Future<void> _shareDoc(BuildContext context) async {
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
        } catch (_) {}
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

  String _safeFileNameWithExt() {
    final base = widget.doc.fileName.trim().isNotEmpty ? widget.doc.fileName.trim() : 'document_${widget.doc.id}';
    String ext = p.extension(base);
    if (ext.isEmpty) {
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

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}