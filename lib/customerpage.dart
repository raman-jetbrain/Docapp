import 'dart:convert';
import 'dart:io';
import 'package:docapp/adduserpage%20.dart';
import 'package:docapp/api/api_constant.dart';
import 'package:docapp/api/customerBus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:docapp/dashboardpage.dart';
import 'package:docapp/customerdetailpage.dart';
import 'package:docapp/documentspage.dart';
import 'package:docapp/dateventspage.dart';
import 'package:docapp/model/customermodel.dart' as model;
import 'package:docapp/storage/Token_storage.dart';
import 'package:http/http.dart' as http;

/* ============================
   API SERVICE
============================ */
class CustomerApiService {
  final String baseUrl = ApiConstants.baseUrl;
  final http.Client _client;

  static const bool _enableHttpLog = true;

  CustomerApiService({http.Client? client}) : _client = client ?? http.Client();

  // Handles both sync and async TokenStorage.getToken() implementations
  Future<String?> _resolveToken() async {
    final Object? maybeFuture = TokenStorage.getToken();
    if (maybeFuture is Future) {
      final t = await maybeFuture;
      return t as String?;
    }
    return maybeFuture as String?;
  }

  Uri _buildUri(String base, String path) {
    final normalizedBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  // --- Logging helpers ---
  void _logRequest({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    String? body,
  }) {
    if (!_enableHttpLog) return;
    debugPrint('[HTTP] $method $uri');
    if (headers != null) {
      final logHeaders = Map<String, String>.from(headers);
      if (logHeaders.containsKey('Authorization')) {
        logHeaders['Authorization'] = 'Bearer ***'; // mask token
      }
      debugPrint('[HTTP] Headers: ${jsonEncode(logHeaders)}');
    }
    if (body != null && body.isNotEmpty) debugPrint('[HTTP] Body: $body');
  }

  void _logResponse(http.Response resp) {
    if (!_enableHttpLog) return;
    debugPrint('[HTTP] <- ${resp.statusCode} ${resp.request?.url}');
    debugPrint('[HTTP] Response body: ${resp.body}');
  }

  // --- GET customers ---
  Future<List<model.Customer>> getCustomers() async {
    final token = await _resolveToken();
    if (token == null || token.isEmpty) {
      debugPrint('[CustomerApi] Missing auth token');
      throw Exception('Missing auth token');
    }

    final uri = _buildUri(baseUrl, '/api/CustomerDataM/GetAsync');
    final headers = {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };

    _logRequest(method: 'GET', uri: uri, headers: headers);
    final resp = await _client.get(uri, headers: headers);
    _logResponse(resp);

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('GET ${uri.path} failed: ${resp.statusCode} ${resp.body}');
    }

    final decoded = json.decode(resp.body);

    // API uses "Response" wrapper
    final List<dynamic> list =
        decoded is Map && decoded['Response'] is List
            ? decoded['Response'] as List
            : (decoded is List ? decoded : const []);

    final customers = list
        .map((e) => _mapApiToCustomer(Map<String, dynamic>.from(e as Map)))
        .toList();

    // De-duplicate by phone
    final seen = <String>{};
    final unique = <model.Customer>[];
    for (final c in customers) {
      if (seen.add(c.phone)) unique.add(c);
    }

    debugPrint('[CustomerApi] Mapped customers: ${unique.length}');
    return unique;
  }

  // Try to read a numeric Id from common keys
  int? _readNumericId(Map<String, dynamic> m) {
    const candidates = [
      'Id', 'ID',
      'CustomerId', 'CustomerID',
      'CustomerDataMId', 'CustomerDataMID',
      'CustomerDataId', 'CustomerDataID',
    ];
    for (final k in candidates) {
      final v = m[k];
      if (v == null) continue;
      if (v is int) return v;
      final parsed = int.tryParse(v.toString());
      if (parsed != null) return parsed;
    }
    final v2 = m['id'];
    if (v2 != null) {
      if (v2 is int) return v2;
      final parsed2 = int.tryParse(v2.toString());
      if (parsed2 != null) return parsed2;
    }
    return null;
  }

  // Normalize phone (digits only)
  String _normalizePhone(String? v) {
    if (v == null) return '';
    return v.replaceAll(RegExp(r'\D+'), '');
  }

  // Map exact keys from your payload + optional base64 image
  model.Customer _mapApiToCustomer(Map<String, dynamic> m) {
    final int? apiIdNum = _readNumericId(m);
    final rawId = (m['Id'] ?? m['ID'] ?? m['CustomerId'] ?? m['CustomerID'] ?? m['id'] ?? '');
    final idString = (apiIdNum != null) ? apiIdNum.toString() : rawId.toString().trim();

    String first = (m['Name'] ?? '').toString().trim();
    String last  = (m['Surname'] ?? '').toString().trim();

    // If Name contains full name and Surname is empty, split
    if (last.isEmpty && first.contains(' ')) {
      final parts = first.split(RegExp(r'\s+'));
      first = parts.isNotEmpty ? parts.first : '';
      last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    }

    final phone   = (m['PhoneNumber'] ?? '').toString().trim();
    final email   = (m['EmailId'] ?? '').toString().trim();
    final address = (m['Address'] ?? '').toString().trim();
    final gender  = (m['Gender'] ?? '').toString().trim();
    final others  = (m['Others'] ?? '').toString().trim();

    // Optional: base64 image via HttpFileData.FileData
    dynamic bytes;
    final httpFile = m['HttpFileData'];
    if (httpFile is Map && httpFile['FileData'] is String) {
      final b64 = (httpFile['FileData'] as String).trim();
      if (b64.isNotEmpty) {
        try {
          bytes = base64Decode(b64); // Uint8List
        } catch (_) {}
      }
    }

    // Build initial map for your model
    final mapForModel = <String, dynamic>{
      'id': idString,                // if your model supports 'id'
      'serverId': idString,          // also store as serverId (string), if your model uses this key
      'name': first,
      'surname': last,
      'phone': phone,
      'email': email,
      'address': address,
      'gender': gender,
      'others': others,
      'imageBytes': bytes,
    };

    final cust = model.Customer.fromMap(mapForModel);
    debugPrint('[Map] apiId=$apiIdNum mappedId="$idString" name=${cust.name} phone=${cust.phone}');
    return cust;
  }

  // NEW: Resolve Id for a specific customer by phone (preferred) then name+surname
  Future<String?> resolveIdForCustomer({
    String? phone,
    String? name,
    String? surname,
  }) async {
    final token = await _resolveToken();
    if (token == null || token.isEmpty) return null;

    final uri = _buildUri(baseUrl, '/api/CustomerDataM/GetAsync');
    final headers = {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };

    _logRequest(method: 'GET', uri: uri, headers: headers);
    final resp = await _client.get(uri, headers: headers);
    _logResponse(resp);

    if (resp.statusCode < 200 || resp.statusCode >= 300) return null;

    final decoded = json.decode(resp.body);
    final List<dynamic> list =
        decoded is Map && decoded['Response'] is List
            ? decoded['Response'] as List
            : (decoded is List ? decoded : const []);

    final normPhone = _normalizePhone(phone ?? '');
    Map<String, dynamic>? found;

    // 1) match by phone
    if (normPhone.isNotEmpty) {
      for (final e in list) {
        if (e is Map<String, dynamic>) {
          final p = _normalizePhone((e['PhoneNumber'] ?? '').toString());
          if (p == normPhone) {
            found = e;
            break;
          }
        }
      }
    }

    // 2) match by name + surname
    if (found == null && (name?.isNotEmpty ?? false)) {
      final nameL = name!.trim().toLowerCase();
      final surL  = (surname ?? '').trim().toLowerCase();
      for (final e in list) {
        if (e is Map<String, dynamic>) {
          final n = (e['Name'] ?? '').toString().trim().toLowerCase();
          final s = (e['Surname'] ?? '').toString().trim().toLowerCase();
          if (n == nameL && s == surL) {
            found = e;
            break;
          }
        }
      }
    }

    if (found == null) return null;

    final idNum = _readNumericId(found);
    final idStr = idNum?.toString() ?? (found['Id']?.toString() ?? '').trim();
    return idStr.isEmpty ? null : idStr;
  }

  // --- DELETE customer (path param; with query fallback) ---
  Future<void> deleteCustomer(String id) async {
    final token = await _resolveToken();
    if (token == null || token.isEmpty) {
      debugPrint('[CustomerApi] Missing auth token');
      throw Exception('Missing auth token');
    }
    final trimmed = id.trim();
    if (trimmed.isEmpty) {
      throw Exception('Empty id passed to delete');
    }

    final encodedId = Uri.encodeComponent(trimmed);
    final headers = {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };

    http.Response? resp;

    // Primary: DELETE /DeleteAsync/{id}
    Uri uri = _buildUri(baseUrl, '/api/CustomerDataM/DeleteAsync/$encodedId');
    _logRequest(method: 'DELETE', uri: uri, headers: headers);
    resp = await _client.delete(uri, headers: headers);
    _logResponse(resp);

    // Fallbacks: query variant and alternate endpoint name (if server differs)
    if (resp.statusCode == 404 || resp.statusCode == 405) {
      final alt1 = _buildUri(baseUrl, '/api/CustomerDataM/DeleteAsync?id=$encodedId');
      _logRequest(method: 'DELETE', uri: alt1, headers: headers);
      resp = await _client.delete(alt1, headers: headers);
      _logResponse(resp);
    }
    if (resp.statusCode == 404 || resp.statusCode == 405) {
      final alt2 = _buildUri(baseUrl, '/api/CustomerDataM/DeleteUnitMasterDetails/$encodedId');
      _logRequest(method: 'DELETE', uri: alt2, headers: headers);
      resp = await _client.delete(alt2, headers: headers);
      _logResponse(resp);
    }
    if (resp.statusCode == 404 || resp.statusCode == 405) {
      final alt3 = _buildUri(baseUrl, '/api/CustomerDataM/DeleteUnitMasterDetails?id=$encodedId');
      _logRequest(method: 'DELETE', uri: alt3, headers: headers);
      resp = await _client.delete(alt3, headers: headers);
      _logResponse(resp);
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('DELETE ${resp.request?.url.path} failed: ${resp.statusCode} ${resp.body}');
    }
  }
}

/* ============================
   CUSTOMER SCREEN
============================ */
class CustomerScreen extends StatefulWidget {
  const CustomerScreen({super.key});

  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
  final CustomerApiService _api = CustomerApiService();

  model.Customer? lastCustomer;
  final List<model.Customer> customers = [];
  List<model.Customer> filteredCustomers = [];
  final TextEditingController _searchController = TextEditingController();

  static const Color kPrimaryBlue = Color(0xFF38B6E4);
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLastCustomer();
    _loadCustomers();
    _searchController.addListener(_filterCustomers);
    CustomerBus.changed.addListener(_onCustomerChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterCustomers);
    _searchController.dispose();
    CustomerBus.changed.removeListener(_onCustomerChanged);
    super.dispose();
  }

  void _onCustomerChanged() {
    final updated = CustomerBus.changed.value;
    if (updated == null) return;

    final idx = customers.indexWhere((c) => c.phone == updated.phone);
    if (idx >= 0) {
      customers[idx] = updated;
    }
    if (lastCustomer?.phone == updated.phone) {
      lastCustomer = updated;
    }
    _filterCustomers();
  }

  Future<void> _loadLastCustomer() async {
    final prefs = await SharedPreferences.getInstance();
    final String? userJson = prefs.getString('last_user');
    if (userJson != null) {
      final Map<String, dynamic> userMap = json.decode(userJson);
      setState(() {
        lastCustomer = model.Customer.fromMap(userMap);
      });
    }
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final prefs = await SharedPreferences.getInstance();

    try {
      final fresh = await _api.getCustomers();
      debugPrint('[UI] fetched customers: ${fresh.length}');

      setState(() {
        customers
          ..clear()
          ..addAll(fresh);
        if (lastCustomer == null && customers.isNotEmpty) {
          lastCustomer = customers.first;
        }
      });

      await prefs.setString('customers', json.encode(customers.map((c) => c.toMap()).toList()));
    } catch (e) {
      final saved = prefs.getString('customers');
      if (saved != null) {
        final List<dynamic> list = json.decode(saved);
        setState(() {
          customers
            ..clear()
            ..addAll(list.map((e) => model.Customer.fromMap(Map<String, dynamic>.from(e))));
        });
      }
      _error = e.toString();
    } finally {
      setState(() => _isLoading = false);
      _filterCustomers();
    }
  }

  void _filterCustomers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      filteredCustomers = customers.where((customer) {
        final nameMatch = customer.name.toLowerCase().contains(query);
        final surnameMatch = customer.surname.toLowerCase().contains(query);
        final phoneMatch = customer.phone.toLowerCase().contains(query);
        return nameMatch || surnameMatch || phoneMatch;
      }).toList();
    });
  }

  void _addNewUser(model.Customer newUser) async {
    setState(() {
      lastCustomer = newUser;
      customers.insert(0, newUser);
      _filterCustomers();
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_user', json.encode(newUser.toMap()));
    await prefs.setString('customers', json.encode(customers.map((c) => c.toMap()).toList()));
  }

  void _navigateToDashboard() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const Dashboardpage()),
    );
  }

  void _navigateToEvents() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DayEventsPage()),
    );
  }

  // --- Delete helpers ---
  void _showSnack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  // NEW: Try to get id from multiple keys, including 'serverId'
  String _extractId(model.Customer c) {
    try {
      final m = c.toMap();
      final raw = m['id'] ??
          m['Id'] ??
          m['CustomerId'] ??
          m['CustomerID'] ??
          m['serverId']; // fallback to serverId if your model uses it
      return (raw?.toString() ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  void _onLongPressCustomer(model.Customer c) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(c);
              },
            ),
            const Divider(height: 0),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(model.Customer c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete customer'),
        content: Text('Are you sure you want to delete ${c.name} ${c.surname}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _deleteCustomer(c);
    }
  }

  Future<void> _deleteCustomer(model.Customer c) async {
    String id = _extractId(c);
    debugPrint('[UI] Requesting delete: id="$id", name=${c.name}, phone=${c.phone}');

    try {
      // Resolve id from API if missing
      if (id.isEmpty) {
        id = (await _api.resolveIdForCustomer(
          phone: c.phone,
          name: c.name,
          surname: c.surname,
        )) ?? '';
        debugPrint('[UI] Resolved id from API: "$id"');
      }

      if (id.isEmpty) {
        throw Exception('Unable to resolve customer id from API. Verify mapping and matching logic.');
      }

      await _api.deleteCustomer(id);

      setState(() {
        customers.removeWhere((x) => _extractId(x) == id || x.phone == c.phone);
        filteredCustomers.removeWhere((x) => _extractId(x) == id || x.phone == c.phone);
        if (lastCustomer != null && (_extractId(lastCustomer!) == id || lastCustomer!.phone == c.phone)) {
          lastCustomer = customers.isNotEmpty ? customers.first : null;
        }
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('customers', json.encode(customers.map((x) => x.toMap()).toList()));
      if (lastCustomer != null) {
        await prefs.setString('last_user', json.encode(lastCustomer!.toMap()));
      } else {
        await prefs.remove('last_user');
      }

      _filterCustomers();
      _showSnack('Customer deleted');
    } catch (e, st) {
      debugPrint('[UI] Delete error: $e\n$st');
      _showSnack('Failed to delete: $e', color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final padding = width * 0.05;
    final isSearching = _searchController.text.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FC),
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverFillRemaining(
            child: Column(
              children: [
                _buildSearchBar(padding),
                if (_isLoading)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  Expanded(
                    child: filteredCustomers.isEmpty
                        ? _buildNoCustomersWithError()
                        : RefreshIndicator(
                            onRefresh: _loadCustomers,
                            child: ListView(
                              padding: EdgeInsets.symmetric(horizontal: padding),
                              children: [
                                if (!isSearching) ...[
                                  Text(
                                    "Last Entered Customer",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: width * 0.045,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  if (lastCustomer != null)
                                    CustomerCard(
                                      customer: lastCustomer!,
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => CustomerDetailPage(
                                              customer: lastCustomer!,
                                            ),
                                          ),
                                        ).then((_) => _loadCustomers());
                                      },
                                      onDocumentsTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => DocumentsPage(
                                              customer: lastCustomer!,
                                            ),
                                          ),
                                        );
                                      },
                                      onLongPress: () => _onLongPressCustomer(lastCustomer!),
                                    ),
                                  const SizedBox(height: 20),
                                  Text(
                                    "All Customers",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: width * 0.045,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                ...filteredCustomers.map((c) {
                                  if (lastCustomer != null && c.phone == lastCustomer!.phone) {
                                    return const SizedBox.shrink();
                                  }
                                  return CustomerCard(
                                    customer: c,
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => CustomerDetailPage(customer: c),
                                        ),
                                      ).then((_) => _loadCustomers());
                                    },
                                    onDocumentsTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => DocumentsPage(customer: c),
                                        ),
                                      );
                                    },
                                    onLongPress: () => _onLongPressCustomer(c),
                                  );
                                }),
                              ],
                            ),
                          ),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 70,
      pinned: true,
      backgroundColor: Colors.transparent,
      leading: const BackButton(color: Colors.white),
      centerTitle: true,
      title: const Text(
        "Customers",
        style: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(blurRadius: 6, color: Colors.black54, offset: Offset(1, 1)),
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
    );
  }

  Widget _buildSearchBar(double padding) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: 15),
      child: Container(
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
    );
  }

  Widget _buildNoCustomersWithError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.people_outline, size: 80, color: Colors.grey),
          const SizedBox(height: 10),
          const Text("No customers found", style: TextStyle(color: Colors.grey, fontSize: 16)),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loadCustomers,
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    final screenWidth = MediaQuery.of(context).size.width;
    final navHeight = screenWidth * 0.18;

    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        height: navHeight,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 25,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavBarItem(Icons.home, 'Home', false, _navigateToDashboard),
            _buildNavBarItem(Icons.group, 'Customers', true, () {}),
            _buildNavBarItem(Icons.add_circle, 'Add', false, () async {
              final newUser = await Navigator.push<model.Customer>(
                context,
                MaterialPageRoute(builder: (context) => const AddNewUserPage()),
              );
              if (newUser != null) _addNewUser(newUser);
            }),
            _buildNavBarItem(Icons.notifications, 'Events', false, _navigateToEvents),
            _buildNavBarItem(Icons.menu, 'Menu', false, () {}),
          ],
        ),
      ),
    );
  }

  Widget _buildNavBarItem(IconData icon, String label, bool isSelected, VoidCallback onTap) {
    final screenWidth = MediaQuery.of(context).size.width;
    final iconSize = screenWidth * 0.07;
    final fontSize = screenWidth * 0.03;

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: isSelected ? kPrimaryBlue : Colors.grey[400],
            size: iconSize,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              color: isSelected ? kPrimaryBlue : Colors.grey[400],
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================
   CUSTOMER CARD
============================ */
class CustomerCard extends StatelessWidget {
  final model.Customer customer;
  final VoidCallback? onTap;
  final VoidCallback? onDocumentsTap;
  final VoidCallback? onLongPress;

  const CustomerCard({
    super.key,
    required this.customer,
    this.onTap,
    this.onDocumentsTap,
    this.onLongPress,
  });

  bool _looksLikeUrl(String? s) =>
      s != null && (s.startsWith('http://') || s.startsWith('https://'));

  @override
  Widget build(BuildContext context) {
    ImageProvider? avatar;

    // 1) Try file path if phone mistakenly stores a path (legacy behavior)
    final photoPath = customer.phone;
    if (photoPath.isNotEmpty && File(photoPath).existsSync()) {
      avatar = FileImage(File(photoPath));
    }

    // 2) Try raw bytes (if provided from API via base64)
    if (avatar == null && customer.imageBytes != null && customer.imageBytes!.isNotEmpty) {
      avatar = MemoryImage(customer.imageBytes!);
    }

    // 3) Try network URL via "others" if it’s a URL string
    if (avatar == null && customer.others is String && _looksLikeUrl(customer.others as String)) {
      avatar = NetworkImage(customer.others as String);
    }

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
            CircleAvatar(
              radius: 30,
              backgroundColor: Colors.blue.shade50,
              backgroundImage: avatar,
              child: avatar == null
                  ? const Icon(Icons.person, size: 30, color: Colors.blueGrey)
                  : null,
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (customer.surname.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      customer.surname,
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
                    customer.phone,
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