import 'dart:convert';
import 'package:docapp/pages/adduserpage%20.dart';
import 'package:docapp/utils/famildetailsutility.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:docapp/api/api_constant.dart';
import 'package:docapp/storage/Token_storage.dart';
import 'package:docapp/model/customer.dart' as model;
import 'package:docapp/pages/customerdetailpage.dart';
import 'package:docapp/documentspage.dart';
import 'package:docapp/utils/customer_utility.dart';

// ========== Logging helpers ==========
const bool kLogHttp = true;

String _maskToken(String? v) {
  if (v == null || v.isEmpty) return '';
  final s = v.replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '').trim();
  if (s.length <= 8) return 'Bearer ****';
  return 'Bearer ${s.substring(0, 4)}****${s.substring(s.length - 4)}';
}

void logReq({
  required String method,
  required String url,
  Map<String, String>? headers,
  Object? body,
}) {
  if (!kLogHttp) return;
  final h = {...?headers};
  if (h.containsKey('Authorization')) h['Authorization'] = _maskToken(h['Authorization']);
  debugPrint('[$method] $url');
  debugPrint('Headers: ${jsonEncode(h)}');
  if (body != null) {
    if (body is String) {
      final trimmed = body.length > 1000 ? '${body.substring(0, 1000)}...(+more)' : body;
      debugPrint('Body: $trimmed');
    } else {
      debugPrint('Body: $body');
    }
  }
}

void logRes(http.Response res) {
  if (!kLogHttp) return;
  final body = res.body;
  final trimmed = body.length > 1500 ? '${body.substring(0, 1500)}...(+more)' : body;
  debugPrint('<- ${res.statusCode} ${res.request?.url}');
  debugPrint(trimmed);
}

// ---------- Helpers ----------
String get _apiBaseNormalized {
  var b = ApiConstants.baseUrl.trim();
  if (b.endsWith('/')) b = b.substring(0, b.length - 1);
  if (!b.toLowerCase().endsWith('/api')) b = '$b/api';
  return b;
}

String get _apiRootNormalized {
  var b = ApiConstants.baseUrl.trim();
  return b;
}

const String kUploadsSegment = '/uploads';

// Build absolute URL from FileName or relative
String? _fileUrlFromName(String? fileName) {
  final fn = (fileName ?? '').trim();
  if (fn.isEmpty) return null;
  if (fn.startsWith('http://') || fn.startsWith('https://')) return fn;
  if (fn.startsWith('/')) return '$_apiRootNormalized$fn';
  return '$_apiRootNormalized$kUploadsSegment/${Uri.encodeComponent(fn)}';
}

// Extract photo URL from HttpFileData (supports Map or List, FileName/fileName)
String? _photoUrlFromHttpFileData(dynamic hfd) {
  if (hfd == null) return null;
  if (hfd is Map) {
    final v = hfd['FileName'] ?? hfd['fileName'];
    if (v is String && v.trim().isNotEmpty) return _fileUrlFromName(v);
  }
  if (hfd is List && hfd.isNotEmpty) {
    final first = hfd.first;
    if (first is Map) {
      final v = first['FileName'] ?? first['fileName'];
      if (v is String && v.trim().isNotEmpty) return _fileUrlFromName(v);
    }
  }
  return null;
}

// Prefer base64 if present in HttpFileData
String? _photoDataUrlFromHttpFileData(dynamic hfd) {
  if (hfd == null) return null;
  if (hfd is Map) {
    final data = (hfd['FileData'] ?? hfd['fileData'])?.toString().trim();
    if (data != null && data.isNotEmpty) {
      return 'data:image/jpeg;base64,$data';
    }
  }
  if (hfd is List && hfd.isNotEmpty && hfd.first is Map) {
    final fm = Map<String, dynamic>.from(hfd.first as Map);
    final data = (fm['FileData'] ?? fm['fileData'])?.toString().trim();
    if (data != null && data.isNotEmpty) {
      return 'data:image/jpeg;base64,$data';
    }
  }
  return null;
}

String? _cleanBearer(String? token) {
  if (token == null) return null;
  return token.replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '').trim();
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

String _fmtDob(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  try {
    final dt = DateTime.parse(iso);
    return "${dt.day}/${dt.month}/${dt.year}";
  } catch (_) {
    return '';
  }
}

// --------------------------------------------------------------------
//                             FAMILY PAGE
// --------------------------------------------------------------------
class FamilyPage extends StatefulWidget {
  final model.Customer customer;
  const FamilyPage({super.key, required this.customer});
  @override
  State<FamilyPage> createState() => _FamilyPageState();
}

class _FamilyPageState extends State<FamilyPage> {
  static const Color kPrimaryBlue = Color(0xFF38B6E4);

  final List<model.Customer> _family = [];
  List<model.Customer> _serverChildren = [];
  Set<String> _serverChildKeys = {};
  List<model.Customer> _filtered = [];

  final TextEditingController _searchController = TextEditingController();
  model.Customer? _parentOverride;
  bool _loadingParent = false;
  String? _loadError;
  bool _preparingChild = false;

  // Cache for child photo URLs fetched via GET /GetAsync/{childId}
  final Map<String, String?> _childPhotoCache = {};

  model.Customer get _parent => _parentOverride ?? widget.customer;
  String _digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

  String _dedupeKey(model.Customer m) {
    final sid = (m.serverId ?? '').toString().trim();
    if (sid.isNotEmpty) return 'id:$sid';
    return 'ph:${_digitsOnly(m.phone)}';
  }

  List<model.Customer> get _membersForUI {
    final seen = <String>{};
    final out = <model.Customer>[];
    void addMember(model.Customer m) {
      final key = _dedupeKey(m);
      if (!seen.contains(key)) {
        seen.add(key);
        out.add(m);
      }
    }
    addMember(_parent);
    for (final c in _serverChildren) addMember(c);
    for (final f in _family) addMember(f);
    return out;
  }

  bool _isPrimary(model.Customer m) => _dedupeKey(m) == _dedupeKey(_parent);

  @override
  void initState() {
    super.initState();
    _loadFamily();
    _searchController.addListener(_filter);
    _fetchParentFromServer();
  }

  @override
  void dispose() {
    _searchController.removeListener(_filter);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFamily() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('customers');
    if (data == null || data.isEmpty) {
      setState(() => _family.clear());
      _filter();
      return;
    }

    try {
      final List<dynamic> customers = json.decode(data);
      final idx = customers.indexWhere((c) => c['phone'] == widget.customer.phone);
      if (idx == -1) {
        setState(() => _family.clear());
        _filter();
        return;
      }

      final parent = Map<String, dynamic>.from(customers[idx]);
      final famList = (parent['family'] as List?) ?? [];
      final members = famList
          .map((e) => model.Customer.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();

      setState(() => _family..clear()..addAll(members));
      _filter();
    } catch (_) {
      setState(() => _family.clear());
      _filter();
    }
  }

  Future<void> _saveFamily() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('customers');
    final List<dynamic> customers =
        data != null && data.isNotEmpty ? json.decode(data) : [];

    final idx = customers.indexWhere((c) => c['phone'] == widget.customer.phone);
    final famMapList = _family.map((m) => m.toMap()).toList();

    if (idx != -1) {
      final parent = Map<String, dynamic>.from(customers[idx]);
      parent['family'] = famMapList;
      customers[idx] = parent;
    } else {
      customers.add({...widget.customer.toMap(), 'family': famMapList});
    }

    await prefs.setString('customers', json.encode(customers));
  }

  void _filter() {
    final q = _searchController.text.toLowerCase();
    final src = _membersForUI;
    setState(() {
      _filtered = src.where((m) {
        final n = m.name.toLowerCase().contains(q);
        final s = m.surname.toLowerCase().contains(q);
        final p = m.phone.toLowerCase().contains(q);
        return n || s || p;
      }).toList();
    });
  }

  Future<String?> _findServerIdInLocalByPhone(String phone) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('customers');
      if (data == null || data.isEmpty) return null;
      final List<dynamic> customers = json.decode(data);
      final idx = customers.indexWhere((c) => c['phone'] == phone);
      if (idx == -1) return null;
      final m = Map<String, dynamic>.from(customers[idx]);
      final candidates = [
        m['serverId'],
        m['Id'],
        m['id'],
        m['CustomerId'],
        m['CustomerDataMId'],
        m['CustomerDataId'],
      ];
      for (final v in candidates) {
        if (v == null) continue;
        final s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
    } catch (_) {}
    return null;
  }

  Future<int?> _verifyAndGetParentIdFromServer(int id) async {
    try {
      final token = await TokenStorage.getToken();
      final jwt = _cleanBearer(token);
      final url = "$_apiBaseNormalized/CustomerDataM/GetAsync/$id";
      final headers = {
        "Accept": "application/json",
        "id": "$id",
        if (jwt != null && jwt.isNotEmpty) "Authorization": "Bearer $jwt",
      };
      logReq(method: 'GET', url: url, headers: headers);
      final res = await http.get(Uri.parse(url), headers: headers);
      logRes(res);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        final map = _unwrapApiPayload(decoded);
        final respId = int.tryParse((map['Id'] ?? '').toString());
        return respId ?? id;
      }
    } catch (e) {
      debugPrint('[Verify] Exception: $e');
    }
    return null;
  }

  Future<int?> _resolveParentServerIdForChildAdd() async {
    String? idStr = (_parentOverride?.serverId ?? '').toString().trim();
    if (idStr.isEmpty) idStr = (widget.customer.serverId ?? '').toString().trim();
    if (idStr.isEmpty) idStr = await _findServerIdInLocalByPhone(_parent.phone);

    final candidate = int.tryParse(idStr ?? '');
    if (candidate == null) return null;
    final verified = await _verifyAndGetParentIdFromServer(candidate);
    return verified ?? candidate;
  }

  // Fetch parent; then fetch profile photo for each child by calling GET /GetAsync/{childId}
  Future<void> _fetchParentFromServer() async {
    String? idStr = (widget.customer.serverId ?? '').toString().trim();
    if (idStr.isEmpty) idStr = await _findServerIdInLocalByPhone(widget.customer.phone);
    if (idStr == null || idStr.isEmpty) return;

    setState(() {
      _loadingParent = true;
      _loadError = null;
    });

    try {
      final token = await TokenStorage.getToken();
      final jwt = _cleanBearer(token);
      final url = "$_apiBaseNormalized/CustomerDataM/GetAsync/$idStr";
      final headers = {
        "Accept": "application/json",
        "id": idStr,
        if (jwt != null && jwt.isNotEmpty) "Authorization": "Bearer $jwt",
      };

      logReq(method: 'GET', url: url, headers: headers);
      final res = await http.get(Uri.parse(url), headers: headers);
      logRes(res);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        final map = _unwrapApiPayload(decoded);
        if (map.isEmpty) return;

        // Parent photo (prefer base64)
        final parentPhoto =
            _photoDataUrlFromHttpFileData(map['HttpFileData']) ??
            _photoUrlFromHttpFileData(map['HttpFileData']) ??
            _fileUrlFromName(map['Photo']?.toString());

        final updatedParent = model.Customer(
          name: (map['Name'] ?? '').toString(),
          surname: (map['Surname'] ?? '').toString(),
          phone: (map['PhoneNumber'] ?? '').toString(),
          email: (map['EmailId'] ?? '').toString(),
          address: (map['Address'] ?? '').toString(),
          dob: _fmtDob(map['DOB']?.toString()),
          gender: (map['Gender'] ?? '').toString().toLowerCase(),
          customEntries: const [],
          photo: parentPhoto,
          serverId: (map['Id'] ?? idStr).toString(),
        );

        // Children (basic info first)
        final children = <model.Customer>[];
        final childs = map['ChildDatas'] ?? map['ChildxDatas'];
        if (childs is List && childs.isNotEmpty) {
          for (final c in childs) {
            if (c is Map) {
              final cm = Map<String, dynamic>.from(c);
              final childId = (cm['Id'] ?? '').toString();
              children.add(
                model.Customer(
                  name: (cm['Name'] ?? '').toString(),
                  surname: (cm['Surname'] ?? '').toString(),
                  phone: (cm['PhoneNumber'] ?? cm['Phone'] ?? '').toString(),
                  email: (cm['EmailId'] ?? cm['Email'] ?? '').toString(),
                  address: (cm['Address'] ?? '').toString(),
                  dob: _fmtDob(cm['DOB']?.toString()),
                  gender: (cm['Gender'] ?? '').toString().toLowerCase(),
                  customEntries: const [],
                  photo: null, // will fill from child's own GET
                  serverId: childId,
                ),
              );
            }
          }
        }

        // Set parent + basic child list immediately
        setState(() {
          _parentOverride = updatedParent;
          _serverChildren = children;
          _serverChildKeys = _serverChildren.map(_dedupeKey).toSet();
          _filter();
        });

        // Now enrich each child's photo using GET /CustomerDataM/GetAsync/{childId}
        if (children.isNotEmpty) {
          await _enrichChildrenPhotos();
        }
      } else {
        setState(() => _loadError = 'HTTP ${res.statusCode}');
      }
    } catch (e) {
      setState(() => _loadError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingParent = false);
    }
  }

  Future<void> _enrichChildrenPhotos() async {
    final ids = _serverChildren
        .map((c) => (c.serverId ?? '').trim())
        .where((id) => id.isNotEmpty)
        .where((id) => !_childPhotoCache.containsKey(id))
        .toSet()
        .toList();

    if (ids.isEmpty) return;

    final futures = ids.map((id) async {
      final url = await _fetchChildPhotoById(id);
      return MapEntry(id, url);
    }).toList();

    final entries = await Future.wait(futures);
    for (final e in entries) {
      _childPhotoCache[e.key] = e.value;
    }

    setState(() {
      _serverChildren = _serverChildren.map((c) {
        final id = (c.serverId ?? '').trim();
        final url = id.isNotEmpty ? _childPhotoCache[id] : null;
        if (url == null || url.isEmpty) return c;
        try {
          final m = c.toMap();
          m['photo'] = url;
          return model.Customer.fromMap(Map<String, dynamic>.from(m));
        } catch (_) {
          return model.Customer(
            name: c.name,
            surname: c.surname,
            phone: c.phone,
            email: c.email,
            address: c.address,
            dob: c.dob,
            gender: c.gender,
            customEntries: const [],
            photo: url,
            serverId: c.serverId,
          );
        }
      }).toList();
      _filter();
    });
  }

  Future<String?> _fetchChildPhotoById(String childId) async {
    try {
      final token = await TokenStorage.getToken();
      final jwt = _cleanBearer(token);
      final url = '$_apiBaseNormalized/CustomerDataM/GetAsync/$childId';
      final headers = {
        'Accept': 'application/json',
        if (jwt != null && jwt.isNotEmpty) 'Authorization': 'Bearer $jwt',
      };
      logReq(method: 'GET', url: url, headers: headers);
      final res = await http.get(Uri.parse(url), headers: headers);
      logRes(res);
      if (res.statusCode < 200 || res.statusCode >= 300) return null;

      final decoded = jsonDecode(res.body);
      final map = _unwrapApiPayload(decoded);

      // Prefer base64 from HttpFileData.FileData
      final dataUrl = _photoDataUrlFromHttpFileData(map['HttpFileData']);
      if (dataUrl != null && dataUrl.isNotEmpty) return dataUrl;

      // Else use filename/url
      final photo = _photoUrlFromHttpFileData(map['HttpFileData']) ??
          _fileUrlFromName(map['Photo']?.toString());
      return photo;
    } catch (e) {
      debugPrint('[ChildPhoto] $childId error: $e');
      return null;
    }
  }

  Future<void> _addMember() async {
    setState(() => _preparingChild = true);
    int? parentId;
    try {
      parentId = await _resolveParentServerIdForChildAdd();
    } finally {
      if (mounted) setState(() => _preparingChild = false);
    }

    final display = [_parent.name, _parent.surname].where((e) => e.trim().isNotEmpty).join(' ');
    final newMember = await Navigator.push<model.Customer?>(
      context,
      MaterialPageRoute(
        builder: (_) => AddNewUserPage(
          parentServerId: parentId,
          parentDisplay: display.isEmpty ? _parent.phone : display,
        ),
      ),
    );

    if (newMember != null) {
      setState(() {
        _family.insert(0, newMember);
        _filter();
      });
      await _saveFamily();
      await _fetchParentFromServer();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Family member added')),
      );
    }
  }

  Future<void> _removeMember(model.Customer member) async {
    if (_isPrimary(member)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can't remove the primary customer.")),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Family Member'),
        content: Text(
          'Do you want to delete ${member.name} ${member.surname}? '
          'This will delete them permanently from the server if synced.',
        ),
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
    if (confirmed != true) return;

    final isServerChild = _serverChildKeys.contains(_dedupeKey(member));

    try {
      if (isServerChild && (member.serverId?.isNotEmpty ?? false)) {
        final token = await TokenStorage.getToken();
        final jwt = _cleanBearer(token);
        final url = Uri.parse('$_apiBaseNormalized/CustomerDataM/DeleteAsync/${member.serverId}');
        final headers = {
          "Accept": "application/json",
          if (jwt != null && jwt.isNotEmpty) "Authorization": "Bearer $jwt",
        };
        logReq(method: 'DELETE', url: url.toString(), headers: headers);
        final res = await http.delete(url, headers: headers);
        logRes(res);

        if (res.statusCode >= 200 && res.statusCode < 300) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Member deleted successfully.")),
          );
          await _fetchParentFromServer();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: HTTP ${res.statusCode}')),
          );
        }
      } else {
        setState(() {
          _family.removeWhere((c) => _dedupeKey(c) == _dedupeKey(member));
          _filter();
        });
        await _saveFamily();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deletion failed: $e')),
      );
    }
  }

  void _openDetails(model.Customer member) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailPage(customer: member)));
  }

  void _openDocs(model.Customer member) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentsPage(customer: member)));
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final pad = width * 0.05;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FC),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 70,
            pinned: true,
            backgroundColor: Colors.transparent,
            leading: const BackButton(color: Colors.white),
            centerTitle: true,
            title: const Text(
              "Family",
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(blurRadius: 6, color: Colors.black54, offset: Offset(1, 1)),
                ],
              ),
            ),
            flexibleSpace: const FlexibleSpaceBar(
              background: DecoratedBox(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage("assets/images/Background2.jpeg"),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),

          // List area
          SliverFillRemaining(
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: pad, vertical: 15),
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blueGrey.withOpacity(0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search, color: Colors.grey),
                            hintText: "Search by name, surname or phone",
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          ),
                        ),
                      ),
                      if (_loadingParent || _loadError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _loadingParent
                                  ? "Refreshing parent from server..."
                                  : "Error: $_loadError",
                              style: TextStyle(
                                fontSize: 12,
                                color: _loadingParent ? Colors.grey : Colors.red,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: _filtered.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.family_restroom_outlined, size: 80, color: Colors.grey),
                              SizedBox(height: 10),
                              Text("No family members found",
                                  style: TextStyle(color: Colors.grey, fontSize: 16)),
                            ],
                          ),
                        )
                      : ListView(
                          padding: EdgeInsets.symmetric(horizontal: pad),
                          children: [
                            Text("Family Members",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: width * 0.045)),
                            const SizedBox(height: 10),
                            ..._filtered.map((member) {
                              return CustomerListCard(
                                member: member,
                                onTap: () => _openDetails(member),
                                onDocumentsTap: () => _openDocs(member),
                                onLongPress: _isPrimary(member) ? null : () => _removeMember(member),
                              );
                            }),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kPrimaryBlue,
        onPressed: _preparingChild ? null : _addMember,
        child: _preparingChild
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

// --------------------------------------------------------------------
//                 CUSTOMER-LIKE CARD FOR FAMILY MEMBERS
// --------------------------------------------------------------------
class CustomerListCard extends StatelessWidget {
  final model.Customer member;
  final VoidCallback? onTap;
  final VoidCallback? onDocumentsTap;
  final VoidCallback? onLongPress;

  const CustomerListCard({
    super.key,
    required this.member,
    this.onTap,
    this.onDocumentsTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.blueGrey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            CustomerAvatar(
              customer: member,
              radius: 30,
              bgColor: Colors.blue.shade50,
              iconColor: Colors.blueGrey,
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (member.surname.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      member.surname,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black54,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    member.phone,
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: onDocumentsTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38B6E4),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text("Docs"),
            ),
          ],
        ),
      ),
    );
  }
}