import 'dart:convert';
import 'package:docapp/pages/adduserpage%20.dart';
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
  final s = v
      .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '')
      .trim();
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
  if (h.containsKey('Authorization')) {
    h['Authorization'] = _maskToken(h['Authorization']);
  }
  debugPrint('[$method] $url');
  debugPrint('Headers: ${jsonEncode(h)}');
  if (body != null) {
    if (body is String) {
      final trimmed = body.length > 1000
          ? '${body.substring(0, 1000)}...(+more)'
          : body;
      debugPrint('Body: $trimmed');
    } else {
      debugPrint('Body: $body');
    }
  }
}

void logRes(http.Response res) {
  if (!kLogHttp) return;
  final body = res.body;
  final trimmed = body.length > 1500
      ? '${body.substring(0, 1500)}...(+more)'
      : body;
  debugPrint('<- ${res.statusCode} ${res.request?.url}');
  debugPrint(trimmed);
}

// ---------- Helpers (top-level) ----------
String get _apiBaseNormalized {
  var b = ApiConstants.baseUrl.trim();
  if (b.endsWith('/')) b = b.substring(0, b.length - 1);
  if (!b.toLowerCase().endsWith('/api')) b = '$b/api';
  return b;
}

String? _cleanBearer(String? token) {
  if (token == null) return null;
  return token
      .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '')
      .trim();
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

class FamilyPage extends StatefulWidget {
  final model.Customer customer;

  const FamilyPage({super.key, required this.customer});

  @override
  State<FamilyPage> createState() => _FamilyPageState();
}

class _FamilyPageState extends State<FamilyPage> {
  static const Color kPrimaryBlue = Color(0xFF38B6E4);

  // Local family (from SharedPreferences)
  final List<model.Customer> _family = [];

  // Children fetched from server (ChildDatas)
  final List<model.Customer> _serverChildren = [];
  Set<String> _serverChildKeys = {};

  List<model.Customer> _filtered = [];
  final TextEditingController _searchController = TextEditingController();

  // Fresh parent from server (if fetched)
  model.Customer? _parentOverride;
  bool _loadingParent = false;
  String? _loadError;

  // Small busy flag when preparing "Add member"
  bool _preparingChild = false;

  model.Customer get _parent => _parentOverride ?? widget.customer;

  String _digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

  // Dedupe key prefers server Id; fallback to phone digits
  String _dedupeKey(model.Customer m) {
    final sid = (m.serverId ?? '').toString().trim();
    if (sid.isNotEmpty) return 'id:$sid';
    return 'ph:${_digitsOnly(m.phone)}';
  }

  // Merge parent + server children + local family. Avoid duplicates.
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

    addMember(_parent); // parent first
    for (final c in _serverChildren) {
      // server children next (preferred)
      addMember(c);
    }
    for (final m in _family) {
      // then local-only children
      addMember(m);
    }
    return out;
  }

  bool _isPrimary(model.Customer m) => _dedupeKey(m) == _dedupeKey(_parent);

  @override
  void initState() {
    super.initState();
    _loadFamily(); // local family
    _searchController.addListener(_filter);
    _fetchParentFromServer(); // refresh parent + children from API
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
      setState(() {
        _family.clear();
      });
      _filter();
      return;
    }

    try {
      final List<dynamic> customers = json.decode(data);
      print(json.decode(data));
      final idx = customers.indexWhere(
        (c) => c['phone'] == widget.customer.phone,
      );
      if (idx == -1) {
        setState(() {
          _family.clear();
        });
        _filter();
        return;
      }

      final parent = Map<String, dynamic>.from(customers[idx]);
      final famList = (parent['family'] as List?) ?? [];
      final members = famList
          .map(
            (e) => model.Customer.fromMap(Map<String, dynamic>.from(e as Map)),
          )
          .toList();

      setState(() {
        _family
          ..clear()
          ..addAll(members);
      });
      _filter();
    } catch (_) {
      setState(() {
        _family.clear();
      });
      _filter();
    }
  }

  Future<void> _saveFamily() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('customers');
    final List<dynamic> customers = data != null && data.isNotEmpty
        ? json.decode(data)
        : [];

    final idx = customers.indexWhere(
      (c) => c['phone'] == widget.customer.phone,
    );
    final familyMapList = _family.map((m) => m.toMap()).toList();

    if (idx != -1) {
      final parent = Map<String, dynamic>.from(customers[idx]);
      parent['family'] = familyMapList;
      customers[idx] = parent;
    } else {
      customers.add({...widget.customer.toMap(), 'family': familyMapList});
    }

    await prefs.setString('customers', json.encode(customers));
  }

  void _filter() {
    final query = _searchController.text.toLowerCase();
    final source = _membersForUI;
    setState(() {
      _filtered = source.where((m) {
        final nameMatch = m.name.toLowerCase().contains(query);
        final surnameMatch = m.surname.toLowerCase().contains(query);
        final phoneMatch = m.phone.toLowerCase().contains(query);
        return nameMatch || surnameMatch || phoneMatch;
      }).toList();
    });
  }

  // ---------- Find serverId locally ----------
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

  // ---------- Verify server id via GET and return the Response.Id (preferred) ----------
  Future<int?> _verifyAndGetParentIdFromServer(int id) async {
    try {
      final token = await TokenStorage.getToken();
      final jwt = _cleanBearer(token);
      final url = "$_apiBaseNormalized/CustomerDataM/GetAsync/$id";
      final headers = <String, String>{
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
        return respId ?? id; // prefer server-provided Id
      } else {
        debugPrint('[Verify] GET failed ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      debugPrint('[Verify] Exception: $e');
    }
    return null;
  }

  // Try to resolve a parent server id:
  Future<int?> _resolveParentServerIdForChildAdd() async {
    String? idStr = (_parentOverride?.serverId ?? '').toString().trim();
    if (idStr.isEmpty) {
      idStr = (widget.customer.serverId ?? '').toString().trim();
    }
    if (idStr.isEmpty) {
      idStr = await _findServerIdInLocalByPhone(_parent.phone);
    }

    debugPrint('[ResolveParent] Local candidate: $idStr');
    final candidate = int.tryParse(idStr ?? '');
    if (candidate == null) return null;

    // Verify via GET and prefer Response.Id
    final verified = await _verifyAndGetParentIdFromServer(candidate);
    debugPrint('[ResolveParent] Verified Id: $verified');
    return verified ?? candidate;
  }

  // ----- Server fetch (refresh parent details + children if we already have an Id) -----
  Future<void> _fetchParentFromServer() async {
    // Prefer the id provided on the incoming customer; fallback to local cache.
    String? idStr = (widget.customer.serverId ?? '').toString().trim();
    if (idStr.isEmpty) {
      idStr = await _findServerIdInLocalByPhone(widget.customer.phone);
    }
    if (idStr == null || idStr.isEmpty) {
      debugPrint('[Fetch] No server id available. Skipping fetch.');
      return;
    }

    setState(() {
      _loadingParent = true;
      _loadError = null;
    });

    try {
      final token = await TokenStorage.getToken();
      final jwt = _cleanBearer(token);

      final url = "$_apiBaseNormalized/CustomerDataM/GetAsync/$idStr";
      final headers = <String, String>{
        "Accept": "application/json",
        "id": idStr,
        if (jwt != null && jwt.isNotEmpty) "Authorization": "Bearer $jwt",
      };

      logReq(method: 'GET', url: url, headers: headers);
      final res = await http.get(Uri.parse(url), headers: headers);
      logRes(res);

      if (res.statusCode == 401) {
        setState(() => _loadError = "Unauthorized. Please log in again.");
        return;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        setState(() => _loadError = "Server error ${res.statusCode}");
        return;
      }

      final decoded = jsonDecode(res.body);
      final map = _unwrapApiPayload(decoded);
      if (map.isEmpty) {
        setState(() => _loadError = "No data returned from server.");
        return;
      }

      // Parent photo URL (HttpFileData.FileName)
      String? parentPhotoUrl;
      final hfd = map['HttpFileData'];
      if (hfd is Map && hfd['FileName'] is String) {
        final fn = hfd['FileName'] as String;
        if (fn.startsWith('http://') || fn.startsWith('https://')) {
          parentPhotoUrl = fn;
        }
      }

      // Build parent customer
      final updated = model.Customer(
        name: (map['Name'] ?? '').toString(),
        surname: (map['Surname'] ?? '').toString(),
        phone: (map['PhoneNumber'] ?? '').toString(),
        email: (map['EmailId'] ?? '').toString(),
        address: (map['Address'] ?? '').toString(),
        dob: _fmtDob(map['DOB']?.toString()),
        gender: (map['Gender'] ?? '').toString().toLowerCase(),
        customEntries: const [],
        photo: parentPhotoUrl,
        imageBytes: null,
        serverId: (map['Id'] ?? idStr).toString(),
        fileId: map['FileId'] is int
            ? map['FileId'] as int
            : int.tryParse("${map['FileId'] ?? ''}"),
      );

      // Parse server children
      final List<model.Customer> children = [];
      final childs = map['ChildDatas'];
      if (childs is List && childs.isNotEmpty) {
        debugPrint('[Fetch] Found ${childs.length} ChildDatas');
        for (final c in childs) {
          if (c is Map) {
            final cm = Map<String, dynamic>.from(c);

            String? childPhotoUrl;
            final chfd = cm['HttpFileData'];
            if (chfd is Map && chfd['FileName'] is String) {
              final fn = chfd['FileName'] as String;
              if (fn.startsWith('http://') || fn.startsWith('https://')) {
                childPhotoUrl = fn;
              }
            }

            final child = model.Customer(
              name: (cm['Name'] ?? '').toString(),
              surname: (cm['Surname'] ?? '').toString(),
              phone: (cm['PhoneNumber'] ?? cm['Phone'] ?? '').toString(),
              email: (cm['EmailId'] ?? cm['Email'] ?? '').toString(),
              address: (cm['Address'] ?? '').toString(),
              dob: _fmtDob(cm['DOB']?.toString()),
              gender: (cm['Gender'] ?? '').toString().toLowerCase(),
              customEntries: const [],
              photo: childPhotoUrl,
              imageBytes: null,
              serverId: (cm['Id'] ?? '').toString(),
              fileId: cm['FileId'] is int
                  ? cm['FileId'] as int
                  : int.tryParse("${cm['FileId'] ?? ''}"),
            );

            children.add(child);
          }
        }
      } else {
        debugPrint('[Fetch] No ChildDatas in response.');
      }

      setState(() {
        _parentOverride = updated;
        _serverChildren
          ..clear()
          ..addAll(children);
        _serverChildKeys = _serverChildren.map(_dedupeKey).toSet();
        _filter();
      });
    } catch (e) {
      setState(() => _loadError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingParent = false);
    }
  }

  // ====== Add member flow (uses AddNewUserPage with ParentCustomerDataId) ======
  Future<void> _addMember() async {
    setState(() => _preparingChild = true);

    int? parentId;
    try {
      parentId = await _resolveParentServerIdForChildAdd();
    } finally {
      if (mounted) setState(() => _preparingChild = false);
    }

    if (parentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Parent is not synced with server; adding as standalone. To add as child, sync parent first.",
          ),
        ),
      );
    }

    final display = [
      _parent.name,
      _parent.surname,
    ].where((e) => e.trim().isNotEmpty).join(' ');
    debugPrint(
      '[AddMember] Navigating to AddNewUserPage with parentServerId=$parentId',
    );
    final newMember = await Navigator.push<model.Customer?>(
      context,
      MaterialPageRoute(
        builder: (_) => AddNewUserPage(
          parentServerId:
              parentId, // null => will create as parent; non-null => as child
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

      // Refresh from server so the child appears under ChildDatas too
      await _fetchParentFromServer();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Family member added')));
      }
    }
  }

  Future<void> _removeMember(model.Customer member) async {
    if (_isPrimary(member)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("You can't remove the primary customer"),
          ),
        );
      }
      return;
    }

    // Prevent removing server children from local cache (no server delete here)
    final isServerChild = _serverChildKeys.contains(_dedupeKey(member));
    if (isServerChild) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "This member is from server. Deletion is not available here.",
          ),
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Family Member'),
        content: const Text('Are you sure you want to remove this member?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() {
        _family.removeWhere((c) => _dedupeKey(c) == _dedupeKey(member));
        _filter();
      });
      await _saveFamily();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Removed')));
      }
    }
  }

  void _openDetails(model.Customer member) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CustomerDetailPage(customer: member)),
    );
  }

  void _openDocs(model.Customer member) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DocumentsPage(customer: member)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final padding = width * 0.05;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FC),
      body: CustomScrollView(
        slivers: [
          // SliverAppBar like CustomerScreen
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
                  Shadow(
                    blurRadius: 6,
                    color: Colors.black54,
                    offset: Offset(1, 1),
                  ),
                ],
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage("assets/images/Background2.jpeg"),
                    fit: BoxFit.cover,
                  ),
                ),
                child: SafeArea(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16, top: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          "assets/images/logo2.png",
                          height: 40,
                          width: 60,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Main content like CustomerScreen
          SliverFillRemaining(
            child: Column(
              children: [
                // Search bar + status
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: padding,
                    vertical: 15,
                  ),
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
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
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
                                color: _loadingParent
                                    ? Colors.grey
                                    : Colors.red,
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
                              Icon(
                                Icons.family_restroom_outlined,
                                size: 80,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 10),
                              Text(
                                "No family members found",
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView(
                          padding: EdgeInsets.symmetric(horizontal: padding),
                          children: [
                            Text(
                              "Family Members",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: width * 0.045,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ..._filtered.map((member) {
                              final isPrimary = _isPrimary(member);
                              final isServerChild =
                                  _serverChildKeys.contains(
                                    _dedupeKey(member),
                                  ) &&
                                  !isPrimary;
                              return FamilyMemberCard(
                                member: member,
                                onTap: () => _openDetails(member),
                                onDocumentsTap: () => _openDocs(member),
                                onLongPress: isPrimary
                                    ? null
                                    : (isServerChild
                                          ? null
                                          : () => _removeMember(member)),
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

      // Floating add button
      floatingActionButton: FloatingActionButton(
        backgroundColor: kPrimaryBlue,
        onPressed: _preparingChild ? null : _addMember,
        child: _preparingChild
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

// Same container design as CustomerCard (copied style)
class FamilyMemberCard extends StatelessWidget {
  final model.Customer member;
  final VoidCallback? onTap;
  final VoidCallback? onDocumentsTap;
  final VoidCallback? onLongPress;

  const FamilyMemberCard({
    super.key,
    required this.member,
    this.onTap,
    this.onDocumentsTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final img = customerImageProvider(member);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress, // long-press to remove (local-only)
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
            CircleAvatar(
              radius: 30,
              backgroundColor: Colors.blue.shade50,
              backgroundImage: img,
              child: img == null
                  ? const Icon(Icons.person, size: 30, color: Colors.blueGrey)
                  : null,
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
