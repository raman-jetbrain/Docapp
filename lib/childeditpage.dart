import 'dart:convert';
import 'dart:io';

import 'package:docapp/api/api_constant.dart';
import 'package:docapp/api/description_api.dart'; // Provides CustomerApi
import 'package:docapp/model/customer.dart';
import 'package:docapp/storage/Token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // for Clipboard
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

// ========= Simple session storage for "open then share" =========
class ShareSessionStorage {
  static String? _title;
  static String? _path;

  static void saveFile({
    required String title,
    required String path,
  }) {
    _title = title;
    _path = path;
  }

  static Future<void> shareFile() async {
    if (_path == null || _path!.isEmpty) return;
    await Share.shareXFiles(
      [XFile(_path!)],
      text: _title ?? '',
    );
  }
}

// ================== Child Data Model ==================
class _ChildData {
  int? id; // existing child ID from server, or null/0 for new
  String name; // child name
  String? gender; // 'male' / 'female' / 'transgender' or similar
  DateTime? dob; // child date of birth

  _ChildData({
    this.id,
    required this.name,
    this.gender,
    this.dob,
  });

  /// Convert to JSON for API.
  /// We now explicitly send ParentCustomerDataId so the backend stores it into ChildData.
  Map<String, dynamic> toJson({
    required String? dobIso,
    required int parentCustomerDataId,
  }) {
    return {
      "Id": id ?? 0, // CHILD row id (0 for new)
      "ParentCustomerDataId": parentCustomerDataId,
      "Name": name,
      "Gender": (gender ?? '').toLowerCase(),
      "DOB": dobIso,
    };
  }
}

class Childeditpage extends StatefulWidget {
  final Customer customer; // The CHILD record to edit
  final int? parentCustomerDataId; // Parent CustomerDataM Id

  const Childeditpage({
    super.key,
    required this.customer,
    this.parentCustomerDataId,
  });

  @override
  State<Childeditpage> createState() => _DescriptionPageState();
}

class _DescriptionPageState extends State<Childeditpage> {
  static const Color kPrimaryBlue = Color(0xFF38B6E4);

  // API
  late final CustomerApi _api;

  // Busy flags
  bool _isLoading = false;
  bool _isSubmitting = false;
  final bool _sharingAll = false;

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

  // Children (grand-children, if any)
  List<_ChildData> _children = [];

  // IDs
  int? _serverId; // Child's CustomerDataM Id
  int? _parentId; // Parent's CustomerDataM Id

  // Local model (child)
  late Customer _customer;

  @override
  void initState() {
    super.initState();
    _api = CustomerApi(baseUrl: ApiConstants.baseUrl);

    // Child passed from FamilyPage
    _customer = widget.customer;

    // Parent id (may be null)
    _parentId = widget.parentCustomerDataId;

    // Child server id, if provided on model
    _serverId = int.tryParse(_customer.serverId ?? '');

    _prefillFromLocal(_customer);

    // If we already know the child's id, fetch directly
    if (_serverId != null) {
      _fetchCustomerById(_serverId!);
    } else {
      // fallback: try to resolve id by phone/name
      _resolveServerIdThenFetch();
    }

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

  // ------------------------ Helpers ------------------------

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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

      final list = await _api.getCustomers(token);
      int? foundId;
      final myPhone = _normPhone(_customer.phone);

      // Match by phone (optional – will be skipped if no phone)
      if (myPhone.isNotEmpty) {
        for (final e in list) {
          if (e is Map) {
            final ph = (e['PhoneNumber'] ?? '').toString();
            if (_normPhone(ph) == myPhone) {
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

      // Fallback by name+surname
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

      final record = await _api.getCustomerById(token, id);
      if (record.isEmpty) return;

      _applyServerRecord(record);
      await _upsertIdInCache(id);

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

    // Parent Id if backend returns ParentCustomerDataId
    final parentIdVal = r['ParentCustomerDataId'];
    if (parentIdVal != null) {
      final pid = parentIdVal is int
          ? parentIdVal
          : int.tryParse(parentIdVal.toString());
      if (pid != null) _parentId = pid;
    }

    // Gender
    final g = (r['Gender'] ?? '').toString().trim().toLowerCase();
    if (g.startsWith('m')) {
      _gender = 'Male';
    } else if (g.startsWith('f')) {
      _gender = 'Female';
    } else if (g.isEmpty) {
      _gender = null;
    } else {
      _gender = 'TransGender';
    }

    // Dates
    final dobIso = (r['DOB'] ?? '').toString();
    _selectedDOB = _tryParseIso(dobIso);
    _dobCtrl.text = _selectedDOB != null ? _fmt(_selectedDOB!) : '';

    final sdobIso = (r['SDOB'] ?? '').toString();
    _selectedRegisteredDOB = _tryParseIso(sdobIso);
    _registeredDobCtrl.text =
        _selectedRegisteredDOB != null ? _fmt(_selectedRegisteredDOB!) : '';

    // Martial/Marital and MarriedDate
    final ms = (r['MartialStatus'] ?? r['MaritalStatus'] ?? '').toString();
    _maritalStatus = ms.isEmpty ? null : ms;

    final marriedIso =
        (r['MarriedDate'] ?? r['MarriageDate'] ?? '').toString();
    _selectedMarriageDate = _tryParseIso(marriedIso);
    _marriageDateCtrl.text =
        _selectedMarriageDate != null ? _fmt(_selectedMarriageDate!) : '';

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
        if (b != null && b.isNotEmpty) {
          setState(() => _avatarBytes = b);
        }
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
          final fileNameOrUrl = (m['Url'] ?? m['url'] ?? fileName).toString();
          final urlStr =
              fileNameOrUrl.isNotEmpty ? _resolveFileUrl(fileNameOrUrl) : '';
          _serverDocs.add(
            _ServerDoc(
              id: id,
              remarks: remarks,
              fileName: fileName.isNotEmpty ? fileName : fileNameOrUrl,
              fileType: fileType,
              url: urlStr.isNotEmpty ? urlStr : null,
            ),
          );
        }
      }
    }

    // Children / grand-children
    _children = [];
    final childList = r['ChildDatas'] ?? r['Children'];
    if (childList is List) {
      for (final c in childList) {
        if (c is Map) {
          final m = Map<String, dynamic>.from(c);
          final idVal = m['Id'] ?? m['id'];
          int? id;
          if (idVal is int) {
            id = idVal;
          } else if (idVal != null) {
            id = int.tryParse(idVal.toString());
          }
          final name = (m['Name'] ?? m['ChildName'] ?? '').toString();
          final gender = (m['Gender'] ?? m['gender'] ?? '').toString();
          final dobStr =
              (m['DOB'] ?? m['Dob'] ?? m['DateOfBirth'] ?? '').toString();
          final dob = _tryParseIso(dobStr);

          if (name.trim().isNotEmpty) {
            _children.add(
              _ChildData(
                id: id,
                name: name,
                gender: gender,
                dob: dob,
              ),
            );
          }
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
    } else if (g.startsWith('f')) {
      _gender = 'Female';
    } else if (g.isEmpty) {
      _gender = null;
    } else {
      _gender = 'TransGender';
    }

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

  String _fmt(DateTime dt) =>
      "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}";

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
    final v =
        m['isDelete'] ?? m['IsDelete'] ?? m['IsDeleted'] ?? m['isDeleted'];
    return _toBool(v);
  }

  // ------------------------ Date pickers ------------------------
  Future<void> _pickDOB() async {
    final initial = _selectedDOB ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDOB = picked;
        _dobCtrl.text = _fmt(picked);
      });
    }
  }

  Future<void> _pickRegisteredDOB() async {
    final initial = _selectedRegisteredDOB ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedRegisteredDOB = picked;
        _registeredDobCtrl.text = _fmt(picked);
      });
    }
  }

  Future<void> _pickMarriageDate() async {
    final initial = _selectedMarriageDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedMarriageDate = picked;
        _marriageDateCtrl.text = _fmt(picked);
      });
    }
  }

  // ------------------------ Custom entries storage ------------------------

  String get _customEntriesStorageKey {
    final phone = _customer.phone.trim();
    final name = _customer.name.trim();
    final surname = _customer.surname.trim();
    // Use braces for all interpolations to avoid $name_ parsing problem
    return 'custom_entries_${phone}_${name}_$surname';
  }

  Future<void> _loadCustomEntries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_customEntriesStorageKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = json.decode(raw);
      if (decoded is! List) return;

      final List<Map<String, String>> list = [];
      for (final e in decoded) {
        if (e is Map) {
          list.add(
            e.map(
              (k, v) => MapEntry(
                k.toString(),
                v?.toString() ?? '',
              ),
            ),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _customEntries = list;
      });
    } catch (e) {
      debugPrint('[_loadCustomEntries] Failed: $e');
    }
  }

  Future<void> _saveCustomEntries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _customEntriesStorageKey,
        json.encode(_customEntries),
      );
    } catch (e) {
      debugPrint('[_saveCustomEntries] Failed: $e');
    }
  }

  Future<void> _addCustomEntry() async {
    final keyCtrl = TextEditingController();
    final valueCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Add custom field'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: keyCtrl,
                decoration: const InputDecoration(labelText: 'Key'),
              ),
              TextField(
                controller: valueCtrl,
                decoration: const InputDecoration(labelText: 'Value'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (result == true &&
        keyCtrl.text.trim().isNotEmpty &&
        valueCtrl.text.trim().isNotEmpty) {
      setState(() {
        _customEntries.add({
          'key': keyCtrl.text.trim(),
          'value': valueCtrl.text.trim(),
        });
      });
      await _saveCustomEntries();
    }
  }

  Future<void> _editCustomEntry(int index) async {
    if (index < 0 || index >= _customEntries.length) return;
    final entry = _customEntries[index];
    final keyCtrl = TextEditingController(text: entry['key'] ?? '');
    final valueCtrl = TextEditingController(text: entry['value'] ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Edit custom field'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: keyCtrl,
                decoration: const InputDecoration(labelText: 'Key'),
              ),
              TextField(
                controller: valueCtrl,
                decoration: const InputDecoration(labelText: 'Value'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result == true &&
        keyCtrl.text.trim().isNotEmpty &&
        valueCtrl.text.trim().isNotEmpty) {
      setState(() {
        _customEntries[index] = {
          'key': keyCtrl.text.trim(),
          'value': valueCtrl.text.trim(),
        };
      });
      await _saveCustomEntries();
    }
  }

  Future<void> _deleteCustomEntry(int index) async {
    if (index < 0 || index >= _customEntries.length) return;
    setState(() {
      _customEntries.removeAt(index);
    });
    await _saveCustomEntries();
  }

  // ------------------------ Fetch documents via POST ------------------------

  Future<List<_ServerDoc>> _fetchDocumentsViaPost(int customerId) async {
    final token = await _resolveToken();
    if (token == null || token.isEmpty) return [];

    // TODO: change the path after baseUrl to match your real API route.
    // Example: https://your-host/api/Customer/GetCustomerDocuments
    final uri = Uri.parse(
      '${ApiConstants.baseUrl.replaceAll(RegExp(r'\/$'), '')}'
      '/Customer/GetCustomerDocuments',
    );

    final body = jsonEncode(<String, dynamic>{
      // Adjust the key name if your API expects something else
      'CustomerDataId': customerId,
    });

    try {
      final resp = await http.post(
        uri,
        headers: {
          HttpHeaders.contentTypeHeader: 'application/json',
          HttpHeaders.authorizationHeader: 'Bearer $token',
        },
        body: body,
      );

      if (resp.statusCode != 200) {
        debugPrint(
          '[_fetchDocumentsViaPost] HTTP ${resp.statusCode}: ${resp.body}',
        );
        return [];
      }

      final decoded = json.decode(resp.body);

      // Try to locate the actual list of documents in the response.
      dynamic docsDyn;
      if (decoded is List) {
        docsDyn = decoded;
      } else if (decoded is Map) {
        docsDyn = decoded['Documents'] ??
            decoded['documents'] ??
            decoded['Data'] ??
            decoded['data'] ??
            decoded['Result'] ??
            decoded['result'];
      }

      if (docsDyn is! List) return [];

      final result = <_ServerDoc>[];
      for (final e in docsDyn) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);

        // Skip deleted docs
        if (_docIsDeleted(m)) continue;

        final id = (m['Id'] ?? m['id'] ?? '').toString();
        final remarks = (m['Remarks'] ?? m['remarks'] ?? '').toString();
        final fileName = (m['FileName'] ?? m['fileName'] ?? '').toString();
        final fileType = (m['FileType'] ?? m['fileType'] ?? '').toString();
        final fileNameOrUrl = (m['Url'] ?? m['url'] ?? fileName).toString();

        final urlStr =
            fileNameOrUrl.isNotEmpty ? _resolveFileUrl(fileNameOrUrl) : '';

        result.add(
          _ServerDoc(
            id: id,
            remarks: remarks,
            fileName: fileName.isNotEmpty ? fileName : fileNameOrUrl,
            fileType: fileType,
            url: urlStr.isNotEmpty ? urlStr : null,
          ),
        );
      }

      return result;
    } catch (e, st) {
      debugPrint('[_fetchDocumentsViaPost] Error: $e\n$st');
      return [];
    }
  }

  // ------------------------ Documents helpers ------------------------

  bool _isImageDoc(_ServerDoc doc) {
    final t = doc.fileType.toLowerCase();
    final name = doc.fileName.toLowerCase();
    final ext = p.extension(name.isNotEmpty ? name : t);
    return t.startsWith('image/') ||
        [
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

  Future<void> _deleteServerDoc(_ServerDoc doc) async {
    setState(() {
      _deletingDocIds.add(doc.id);
    });

    try {
      // TODO: Add your backend delete call here, for example:
      // final token = await _resolveToken();
      // await _api.deleteDocument(token, doc.id);
      await Future.delayed(const Duration(milliseconds: 300));

      if (!mounted) return;
      setState(() {
        _serverDocs.removeWhere((d) => d.id == doc.id);
      });
      _showSnack('Document removed (local only, add API call).');
    } catch (e) {
      _showSnack('Failed to delete document: $e');
    } finally {
      if (mounted) {
        setState(() {
          _deletingDocIds.remove(doc.id);
        });
      }
    }
  }

  // ------------------------ Save / Share stubs ------------------------

  Future<void> _saveAll() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      // TODO: Implement your "save customer" logic here:
      //  - Build a JSON body from controllers
      //  - Include ChildDatas if needed
      //  - Call your API via _api or http
      await Future.delayed(const Duration(milliseconds: 300));
      _showSnack('Save not implemented – connect to backend.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _shareCustomer() async {
    final b = StringBuffer();
    b.writeln('${_nameCtrl.text} ${_surnameCtrl.text}');
    if (_phoneCtrl.text.trim().isNotEmpty) {
      b.writeln('Phone: ${_phoneCtrl.text}');
    }
    if (_emailCtrl.text.trim().isNotEmpty) {
      b.writeln('Email: ${_emailCtrl.text}');
    }
    if (_addressCtrl.text.trim().isNotEmpty) {
      b.writeln('Address: ${_addressCtrl.text}');
    }
    if (_dobCtrl.text.trim().isNotEmpty) {
      b.writeln('DOB: ${_dobCtrl.text}');
    }
    if (_maritalStatus != null && _maritalStatus!.trim().isNotEmpty) {
      b.writeln('Marital status: $_maritalStatus');
    }
    if (_othersCtrl.text.trim().isNotEmpty) {
      b.writeln('Others: ${_othersCtrl.text}');
    }

    if (_customEntries.isNotEmpty) {
      b.writeln('\nCustom fields:');
      for (final e in _customEntries) {
        final k = e['key'] ?? '';
        final v = e['value'] ?? '';
        if (k.isNotEmpty && v.isNotEmpty) {
          b.writeln('- $k: $v');
        }
      }
    }

    await Share.share(b.toString());
  }

  // ------------------------ UI builders ------------------------

  Widget _buildGenderChips() {
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Male'),
          selected: _gender == 'Male',
          onSelected: (v) {
            setState(() {
              _gender = v ? 'Male' : null;
            });
          },
        ),
        ChoiceChip(
          label: const Text('Female'),
          selected: _gender == 'Female',
          onSelected: (v) {
            setState(() {
              _gender = v ? 'Female' : null;
            });
          },
        ),
        ChoiceChip(
          label: const Text('Transgender'),
          selected: _gender == 'TransGender',
          onSelected: (v) {
            setState(() {
              _gender = v ? 'TransGender' : null;
            });
          },
        ),
      ],
    );
  }

  Widget _buildMaritalDropdown() {
    final items = <String>[
      'Single',
      'Married',
      'others',
    ];
    return DropdownButtonFormField<String>(
      initialValue: _maritalStatus != null && _maritalStatus!.isNotEmpty
          ? _maritalStatus
          : null,
      items: items
          .map(
            (e) => DropdownMenuItem<String>(
              value: e,
              child: Text(e),
            ),
          )
          .toList(),
      onChanged: (v) {
        setState(() {
          _maritalStatus = v;
        });
      },
      decoration: const InputDecoration(
        labelText: 'Marital status',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildCustomEntriesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Custom fields',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: _addCustomEntry,
              tooltip: 'Add custom field',
            ),
          ],
        ),
        if (_customEntries.isEmpty)
          const Text(
            'No custom fields',
            style: TextStyle(color: Colors.black54),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _customEntries.length,
            itemBuilder: (_, i) {
              final e = _customEntries[i];
              final k = e['key'] ?? '';
              final v = e['value'] ?? '';
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text(k),
                  subtitle: Text(v),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _editCustomEntry(i),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteCustomEntry(i),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildDocumentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Documents',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        if (_serverDocs.isEmpty && !_isLoading)
          const Text(
            'No documents found',
            style: TextStyle(color: Colors.black54),
          ),
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          ),
        if (_serverDocs.isNotEmpty)
          Column(
            children: _serverDocs
                .map(
                  (doc) => _ServerDocCard(
                    doc: doc,
                    isImage: _isImageDoc(doc),
                    fetchBytes: _fetchBytesWithAuth,
                    deleting: _deletingDocIds.contains(doc.id),
                    onDelete: () => _deleteServerDoc(doc),
                    onEdit: null,
                    onInfo: null,
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  Widget _buildChildrenSection() {
    if (_children.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Children',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _children.length,
          itemBuilder: (_, i) {
            final c = _children[i];
            final dob = c.dob != null ? _fmt(c.dob!) : '';
            return ListTile(
              leading: const Icon(Icons.child_care),
              title: Text(c.name),
              subtitle: Text(
                  '${c.gender ?? ''}${dob.isNotEmpty ? ' · $dob' : ''}'),
            );
          },
        ),
      ],
    );
  }

  // ------------------------ Build ------------------------
  @override
  Widget build(BuildContext context) {
    final avatar = _avatarBytes;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Child details'),
        backgroundColor: kPrimaryBlue,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareCustomer,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSubmitting ? null : _saveAll,
        label: _isSubmitting
            ? const Text('Saving...')
            : const Text('Save'),
        icon: _isSubmitting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.save_outlined),
        backgroundColor: kPrimaryBlue,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                Center(
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.grey.shade300,
                    backgroundImage:
                        avatar != null ? MemoryImage(avatar) : null,
                    child: avatar == null
                        ? const Icon(Icons.person, size: 40)
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                // Name fields
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'First name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _surnameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Surname',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // PHONE – OPTIONAL (not compulsory)
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // ADDRESS – MULTI-LINE, GROWS WITH CONTENT (line by line)
                TextField(
                  controller: _addressCtrl,
                  keyboardType: TextInputType.multiline,
                  minLines: 2,
                  maxLines: null, // allow as many lines as needed
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 16),
                const Text(
                  'Gender',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildGenderChips(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _dobCtrl,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'DOB',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today_outlined),
                        ),
                        onTap: _pickDOB,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _registeredDobCtrl,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Registered DOB',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today_outlined),
                        ),
                        onTap: _pickRegisteredDOB,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _marriageDateCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Marriage date',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  onTap: _pickMarriageDate,
                ),
                const SizedBox(height: 12),
                _buildMaritalDropdown(),
                const SizedBox(height: 12),
                TextField(
                  controller: _othersCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Others',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                _buildCustomEntriesSection(),
                const SizedBox(height: 24),
                _buildChildrenSection(),
                const SizedBox(height: 24),
                _buildDocumentsSection(),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black12,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
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
      appBar: AppBar(
        title: Text(title?.trim().isNotEmpty == true ? title! : 'Image'),
        backgroundColor: const Color(0xFF38B6E4),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () async {
              await ShareSessionStorage.shareFile();
            },
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: InteractiveViewer(
        minScale: 0.5,
        maxScale: 5,
        child: Center(child: Image.memory(bytes)),
      ),
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
    if (widget.isImage &&
        widget.doc.url != null &&
        widget.doc.url!.isNotEmpty) {
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
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Write bytes to a temp file and store in session storage.
  Future<File?> _storeInSession(Uint8List bytes) async {
    try {
      final dir = await getTemporaryDirectory();
      final name = _safeFileNameWithExt();
      final path = p.join(dir.path, name);
      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      ShareSessionStorage.saveFile(
        title: widget.doc.fileName,
        path: file.path,
      );
      return file;
    } catch (e) {
      _snack(context, 'Failed to cache file: $e');
      return null;
    }
  }

  IconData _iconForType() {
    final t = widget.doc.fileType.toLowerCase();
    final name = widget.doc.fileName.toLowerCase();
    final ext = p.extension(name.isNotEmpty ? name : t);
    if (t.startsWith('image/') ||
        [
          '.png',
          '.jpg',
          '.jpeg',
          '.gif',
          '.webp',
          '.bmp',
          '.tif',
          '.tiff',
          '.heic'
        ].contains(ext)) {
      return Icons.image_outlined;
    }
    if (t.contains('pdf') || ext == '.pdf') {
      return Icons.picture_as_pdf_outlined;
    }
    if (t.contains('sheet') ||
        t.contains('excel') ||
        ext == '.xls' ||
        ext == '.xlsx' ||
        ext == '.csv') {
      return Icons.grid_on_outlined;
    }
    if (t.contains('word') ||
        ext == '.doc' ||
        ext == '.docx' ||
        ext == '.rtf') {
      return Icons.description_outlined;
    }
    if (t.contains('text') || ext == '.txt' || ext == '.log') {
      return Icons.notes_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openPreview(context),
      child: Container(
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
                        fontWeight: FontWeight.w600, color: Colors.black87),
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
                  if (widget.doc.url != null &&
                      widget.doc.url!.trim().isNotEmpty) ...[
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
                      const Spacer(),
                      if (widget.onInfo != null)
                        IconButton(
                          tooltip: 'Details',
                          onPressed: widget.deleting ? null : widget.onInfo,
                          icon: const Icon(Icons.info_outline,
                              color: Colors.black87),
                        ),
                      if (widget.onEdit != null)
                        IconButton(
                          tooltip: 'Rename',
                          onPressed: widget.deleting ? null : widget.onEdit,
                          icon: const Icon(Icons.edit_outlined,
                              color: Colors.black87),
                        ),
                      if (widget.onDelete != null)
                        IconButton(
                          tooltip: 'Delete',
                          onPressed: widget.deleting ? null : widget.onDelete,
                          icon: Icon(Icons.delete_outline,
                              color:
                                  widget.deleting ? Colors.grey : Colors.red),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePreview() {
    if (_loading) {
      return Container(
        color: Colors.grey.shade100,
        child: const Center(
          child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (_failed || _bytes == null || _bytes!.isEmpty) {
      return Container(
        color: Colors.grey.shade100,
        child: const Center(
            child: Icon(Icons.broken_image_outlined, color: Colors.black38)),
      );
    }
    return Image.memory(
      _bytes!,
      fit: BoxFit.cover,
      width: 56,
      height: 56,
    );
  }

  Future<void> _openPreview(BuildContext context) async {
    // IMAGE DOCUMENT
    if (widget.isImage) {
      if (_bytes == null || _bytes!.isEmpty) {
        await _loadBytes();
      }
      if (!mounted) return;
      if (_bytes == null || _bytes!.isEmpty) {
        _snack(context, 'Unable to load image');
        return;
      }

      // Save to temp and store in session
      final file = await _storeInSession(_bytes!);
      if (file == null) return;

      // Open viewer with share button
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

    // NON-IMAGE DOCUMENT (e.g., pdf, doc)
    // Download bytes, store in temp, then share via session storage.
    if (widget.doc.url != null && widget.doc.url!.isNotEmpty) {
      try {
        final b = await widget.fetchBytes(widget.doc.url!);
        if (b == null || b.isEmpty) {
          _snack(context, 'Unable to download file');
          return;
        }
        final file = await _storeInSession(b);
        if (file == null) return;
        await ShareSessionStorage.shareFile();
      } catch (e) {
        _snack(context, 'Unable to open file: $e');
      }
    } else {
      _snack(context, 'No preview available');
    }
  }

  String _safeFileNameWithExt() {
    final base = widget.doc.fileName.trim().isNotEmpty
        ? widget.doc.fileName.trim()
        : 'document_${widget.doc.id}';
    String ext = p.extension(base);
    if (ext.isEmpty) {
      final t = widget.doc.fileType.toLowerCase();
      if (t.startsWith('image/')) {
        ext = '.${t.split('/').last}';
      } else if (widget.doc.url != null &&
          widget.doc.url!.contains('.')) {
        ext = p.extension(Uri.parse(widget.doc.url!).path);
      } else {
        ext = widget.isImage ? '.jpg' : '.bin';
      }
    }
    if (!base.endsWith(ext)) {
      return '$base$ext';
    }
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}