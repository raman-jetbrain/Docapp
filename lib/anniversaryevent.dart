import 'dart:convert';
import 'package:docapp/birthdaylist.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:docapp/api/customer_api_service.dart';
import 'package:docapp/dashboardpage.dart';
import 'package:docapp/pages/adduserpage%20.dart';
import 'package:docapp/pages/customerdetailpage.dart';
import 'package:docapp/documentspage.dart';
import 'package:docapp/model/customer.dart' as model;
import 'package:docapp/postereditpage.dart';

class AnniversaryPage extends StatefulWidget {
  const AnniversaryPage({super.key});

  @override
  State<AnniversaryPage> createState() => _AnniversaryPageState();
}

class _AnniversaryPageState extends State<AnniversaryPage> {
  static const Color kPrimaryBlue = Color(0xFF38B6E4);

  // Use your API service (no GetAsync/{id} calls in this page)
  final CustomerApiService _api = CustomerApiService();

  bool _isLoading = false;
  String? _error;

  List<_CustomerWithAnniv> _enriched = [];
  List<_CustomerWithAnniv> _matches = [];
  DateTime _selectedDate = DateTime.now();

  // Cache keys (customer + parsed anniversary + avatarUrl)
  static const _kAnnivCache = 'anniversary_customers_local_v1';
  static const _kAnnivCacheUpdatedAt = 'anniversary_customers_updated_at_v1';

  @override
  void initState() {
    super.initState();
    _loadAnniversaries();
  }

  // Load from local storage first; if empty, fetch from API and cache
  Future<void> _loadAnniversaries() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final cached = await _loadAnnivCache();
      if (cached.isNotEmpty && mounted) {
        setState(() {
          _enriched = cached;
          _applyDateFilter();
        });
        setState(() => _isLoading = false);
        return;
      }
    } catch (_) {}

    // If no cache, fetch once from API and cache it
    try {
      final fresh = await _fetchEnrichedFromApi();
      await _saveAnnivCache(fresh);
      if (!mounted) return;
      setState(() {
        _enriched = fresh;
        _applyDateFilter();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Manual refresh: fetch GetAllAsync again and update cache
  Future<void> _refreshFromApi() async {
    setState(() => _isLoading = true);
    try {
      final fresh = await _fetchEnrichedFromApi();
      await _saveAnnivCache(fresh);
      if (!mounted) return;
      setState(() {
        _enriched = fresh;
        _applyDateFilter();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Build enriched list from GetAllAsync ONLY (no GetAsync/{id})
  Future<List<_CustomerWithAnniv>> _fetchEnrichedFromApi() async {
    final basics = await _api
        .getCustomers(); // must return the Response[] array
    if (basics.isEmpty) return [];

    return basics
        .map((c) {
          final m = _safeToMap(c);
          final ann = _annivFromAnyMap(m); // reads MarriedDate et al
          final avatarUrl = _imageUrlFromAnyMap(
            m,
          ); // reads HttpFileData.FileName or Others
          return _CustomerWithAnniv(
            customer: c,
            anniversary: ann,
            avatarUrl: avatarUrl,
          );
        })
        .toList(growable: false);
  }

  void _applyDateFilter() {
    final filtered = _enriched
        .where((x) => _matchesMonthDay(x.anniversary, _selectedDate))
        .toList();
    filtered.sort((a, b) {
      final as = '${a.customer.surname} ${a.customer.name}'
          .toLowerCase()
          .trim();
      final bs = '${b.customer.surname} ${b.customer.name}'
          .toLowerCase()
          .trim();
      return as.compareTo(bs);
    });
    _matches = filtered;
  }

  // -----------------------------
  // Cache enriched list
  // -----------------------------
  Future<void> _saveAnnivCache(List<_CustomerWithAnniv> items) async {
    final prefs = await SharedPreferences.getInstance();
    final list = items.map((e) {
      final cm = _safeToMap(e.customer);
      cm.remove('imageBytes'); // avoid raw bytes in prefs
      return {
        'customer': _jsonSafeMap(cm),
        'anniversary': e.anniversary?.toIso8601String(),
        'avatarUrl': e.avatarUrl,
      };
    }).toList();

    await prefs.setString(_kAnnivCache, jsonEncode(list));
    await prefs.setString(
      _kAnnivCacheUpdatedAt,
      DateTime.now().toIso8601String(),
    );
  }

  Future<List<_CustomerWithAnniv>> _loadAnnivCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAnnivCache);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      return list
          .map<_CustomerWithAnniv>((e) {
            final custMap = Map<String, dynamic>.from(e['customer'] as Map);
            final cust = model.Customer.fromMap(custMap);
            final annStr = e['anniversary']?.toString();
            final ann = annStr == null || annStr.isEmpty
                ? null
                : DateTime.tryParse(annStr);
            final avatarUrl = e['avatarUrl']?.toString();
            return _CustomerWithAnniv(
              customer: cust,
              anniversary: ann,
              avatarUrl: avatarUrl,
            );
          })
          .toList(growable: false);
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic> _jsonSafeMap(Map<String, dynamic> input) {
    final out = <String, dynamic>{};
    input.forEach((k, v) => out[k] = _jsonSafeValue(v));
    return out;
  }

  dynamic _jsonSafeValue(dynamic v) {
    if (v == null) return null;
    if (v is Uint8List) return base64Encode(v);
    if (v is DateTime) return v.toIso8601String();
    if (v is Map) return _jsonSafeMap(Map<String, dynamic>.from(v));
    if (v is List) return v.map(_jsonSafeValue).toList();
    if (v is num || v is String || v is bool) return v;
    return v.toString();
  }

  // -----------------------------
  // Anniversary parsing and helpers
  // -----------------------------

  Map<String, dynamic> _safeToMap(model.Customer c) {
    try {
      return c.toMap();
    } catch (_) {
      return {};
    }
  }

  // Pick MarriedDate (and variants) directly from the list item
  DateTime? _annivFromAnyMap(Map<String, dynamic> root) {
    final keys = {
      'MarriedDate',
      'marriedDate',
      'MarriageDate',
      'marriageDate',
      'AnniversaryDate',
      'anniversaryDate',
      'Anniversary',
      'anniversary',
      'WeddingDate',
      'weddingDate',
      'MarriedOn',
      'marriedOn',
      'DateOfMarriage',
      'dateOfMarriage',
      'DOM',
      'dom',
      'DOA',
      'doa',
    };

    // Direct flat check
    for (final entry in root.entries) {
      final k = entry.key.toString();
      if (keys.contains(k) || keys.contains(k.toLowerCase())) {
        final d = _parseDateFlex(entry.value);
        if (d != null) return d;
      }
    }

    // Deep search (nested maps/lists)
    final val = _findValueByKeysDeep(
      root,
      keys.map((e) => e.toString().toLowerCase()).toSet(),
    );
    if (val != null) {
      final d = _parseDateFlex(val);
      if (d != null) return d;
    }

    // Free-text fallback
    final others = (root['others'] ?? root['Others'])?.toString().trim();
    if (others != null && others.isNotEmpty) {
      final d = _readDateFromFreeText(others);
      if (d != null) return d;
    }
    return null;
  }

  // Extract avatar URL from HttpFileData.FileName or Others
  String? _imageUrlFromAnyMap(Map<String, dynamic> root) {
    try {
      final http = root['HttpFileData'] ?? root['httpFileData'];
      if (http is Map) {
        final u = (http['FileName'] ?? http['fileName'])?.toString();
        if (u != null && u.startsWith('http')) return u;
      }
    } catch (_) {}
    final others = (root['Others'] ?? root['others'])?.toString();
    if (others != null && others.startsWith('http')) return others;
    return null;
  }

  dynamic _findValueByKeysDeep(
    dynamic node,
    Set<String> keysLower, [
    int depth = 0,
  ]) {
    if (node == null || depth > 6) return null;

    if (node is Map) {
      for (final entry in node.entries) {
        final k = entry.key.toString().toLowerCase();
        if (keysLower.contains(k)) return entry.value;
      }
      for (final entry in node.entries) {
        final v = _findValueByKeysDeep(entry.value, keysLower, depth + 1);
        if (v != null) return v;
      }
    } else if (node is List) {
      for (final item in node) {
        final v = _findValueByKeysDeep(item, keysLower, depth + 1);
        if (v != null) return v;
      }
    }
    return null;
  }

  DateTime? _readDateFromFreeText(String text) {
    final reg = RegExp(
      r'(marriage\s*date|married\s*(date|on)|wedding\s*date|doa|dom)\s*[:\-]?\s*([0-9A-Za-z/\-\. ]{4,})',
      caseSensitive: false,
    );
    final m = reg.firstMatch(text);
    if (m == null) return null;
    final raw = (m.group(3) ?? '').trim();
    final cleaned = raw.split(RegExp(r'[^0-9A-Za-z/\-\. ]')).first.trim();
    return _parseDateFlex(cleaned);
  }

  DateTime? _parseDateFlex(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.isUtc ? v.toLocal() : v;

    final s0 = v.toString().trim();
    if (s0.isEmpty || s0.toLowerCase() == 'null') return null;

    // .NET /Date(ms)/
    final mNet = RegExp(r'^/Date\((\d+)\)/$').firstMatch(s0);
    if (mNet != null) {
      final ms = int.tryParse(mNet.group(1)!);
      if (ms != null) {
        return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
      }
    }

    // digits-only epoch
    if (RegExp(r'^\d+$').hasMatch(s0)) {
      final n = int.tryParse(s0);
      if (n != null) {
        if (s0.length >= 12) {
          return DateTime.fromMillisecondsSinceEpoch(n, isUtc: true).toLocal();
        }
        if (s0.length == 10) {
          return DateTime.fromMillisecondsSinceEpoch(
            n * 1000,
            isUtc: true,
          ).toLocal();
        }
      }
    }

    // ISO
    final iso = DateTime.tryParse(s0);
    if (iso != null) return iso.isUtc ? iso.toLocal() : iso;

    // dd-MM-yyyy, dd/MM/yyyy, dd-MM, yyyy-MM-dd, etc.
    final s = s0.replaceAll('/', '-').replaceAll('.', '-');
    final parts = s.split('-').where((e) => e.trim().isNotEmpty).toList();

    if (parts.length >= 3) {
      if (parts[0].length == 4) {
        final y = int.tryParse(parts[0]) ?? 0;
        final mm = int.tryParse(parts[1]) ?? 0;
        final dd = int.tryParse(parts[2]) ?? 0;
        if (y > 0 && mm > 0 && dd > 0) return DateTime(y, mm, dd);
      } else {
        final dd = int.tryParse(parts[0]) ?? 0;
        final mm = int.tryParse(parts[1]) ?? 0;
        int y = int.tryParse(parts[2]) ?? 0;
        if (y > 0 && y < 100) y += 2000;
        if (y > 0 && mm > 0 && dd > 0) return DateTime(y, mm, dd);
      }
    }

    if (parts.length == 2) {
      final now = DateTime.now();
      final dd = int.tryParse(parts[0]) ?? 0;
      final mm = int.tryParse(parts[1]) ?? 0;
      if (mm > 0 && dd > 0) return DateTime(now.year, mm, dd);
    }

    final nums = RegExp(r'\d+').allMatches(s0).map((m) => m.group(0)!).toList();
    if (nums.length >= 3 && nums[0].length == 4) {
      final y = int.tryParse(nums[0]) ?? 0;
      final mm = int.tryParse(nums[1]) ?? 0;
      final dd = int.tryParse(nums[2]) ?? 0;
      if (y > 0 && mm > 0 && dd > 0) return DateTime(y, mm, dd);
    } else if (nums.length >= 2) {
      final now = DateTime.now();
      final dd = int.tryParse(nums[0]) ?? 0;
      final mm = int.tryParse(nums[1]) ?? 0;
      if (mm > 0 && dd > 0) return DateTime(now.year, mm, dd);
    }

    return null;
  }

  bool _isLeap(int y) {
    if (y % 400 == 0) return true;
    if (y % 100 == 0) return false;
    return y % 4 == 0;
  }

  bool _matchesMonthDay(DateTime? dt, DateTime on) {
    if (dt == null) return false;
    if (dt.month == 2 && dt.day == 29) {
      return on.month == 2 &&
          (on.day == 29 || (!_isLeap(on.year) && on.day == 28));
    }
    return dt.month == on.month && dt.day == on.day;
  }

  String _formatDate(DateTime d, {bool includeYear = false}) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final base = '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]}';
    return includeYear ? '$base ${d.year}' : base;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _applyDateFilter();
    }
  }

  // -----------------------------
  // Navigation helpers
  // -----------------------------
  void _navigateToDashboard() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const Dashboardpage()),
    );
  }

  void _navigateToCustomers() {
    Navigator.pop(context);
  }

  void _navigateToAddUserPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddNewUserPage()),
    );
  }

  void _navigateToEvents() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AnniversaryPage()),
    );
  }

  void _openBirthdays() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const BirthdayPage()),
    );
  }

  Future<void> _openCustomerDetail(model.Customer baseCustomer) async {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerDetailPage(customer: baseCustomer),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final padding = width * 0.05;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FC),
      body: RefreshIndicator(
        onRefresh: _refreshFromApi, // manual refresh updates local cache
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 70,
              pinned: true,
              backgroundColor: Colors.transparent,
              leading: Navigator.canPop(context)
                  ? const BackButton(color: Colors.white)
                  : const SizedBox.shrink(),
              centerTitle: true,
              title: const Text(
                "Wedding Anniversaries",
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
              actions: [
                IconButton(
                  tooltip: 'Pick date',
                  icon: const Icon(
                    Icons.calendar_today_outlined,
                    color: Colors.white,
                  ),
                  onPressed: _pickDate,
                ),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: _refreshFromApi,
                ),
              ],
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

            // Header with switch
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: padding,
                  vertical: 12,
                ),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blueGrey.withOpacity(0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _EventSwitchBar(
                        showAnniversaries: true,
                        onBirthdaysTap: _openBirthdays,
                        onAnniversariesTap: () {},
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.favorite, color: Colors.pink),
                          const SizedBox(width: 10),
                          Text(
                            'Anniversaries on ${_formatDate(_selectedDate, includeYear: true)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setState(() => _selectedDate = DateTime.now());
                              _applyDateFilter();
                            },
                            child: const Text('Today'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Content
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: padding),
                child: Builder(
                  builder: (_) {
                    if (_isLoading && _enriched.isEmpty) {
                      return SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: const Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (_error != null && _enriched.isEmpty) {
                      return SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: _refreshFromApi,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    if (_matches.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                            'No wedding anniversaries on ${_formatDate(_selectedDate, includeYear: true)}',
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                        ),
                      );
                    }

                    return Column(
                      children: [
                        const SizedBox(height: 12),
                        ..._matches.map(
                          (e) => EventCustomerCard(
                            customer: e.customer,
                            subtitle: e.anniversary != null
                                ? '💍 ${_formatDate(e.anniversary!, includeYear: false)}'
                                : null,
                            avatarUrlOverride: e.avatarUrl,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PosterSharePage(customer: e.customer),
                                ),
                              );
                            },
                            onDocumentsTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      DocumentsPage(customer: e.customer),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  // Bottom nav (marks Events selected)
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
            _buildNavBarItem(
              Icons.group,
              'Customers',
              false,
              _navigateToCustomers,
            ),
            _buildNavBarItem(
              Icons.add_circle,
              'Add',
              false,
              _navigateToAddUserPage,
            ),
            _buildNavBarItem(
              Icons.notifications,
              'Events',
              true,
              _navigateToEvents,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavBarItem(
    IconData icon,
    String label,
    bool isSelected,
    VoidCallback onTap,
  ) {
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

class _CustomerWithAnniv {
  final model.Customer customer;
  final DateTime? anniversary;
  final String? avatarUrl;
  const _CustomerWithAnniv({
    required this.customer,
    required this.anniversary,
    this.avatarUrl,
  });
}

class EventCustomerCard extends StatelessWidget {
  final model.Customer customer;
  final String? subtitle;
  final String? avatarUrlOverride;
  final VoidCallback? onTap;
  final VoidCallback? onDocumentsTap;

  const EventCustomerCard({
    super.key,
    required this.customer,
    this.subtitle,
    this.avatarUrlOverride,
    this.onTap,
    this.onDocumentsTap,
  });

  bool _looksLikeUrl(String? s) =>
      s != null && (s.startsWith('http://') || s.startsWith('https://'));

  Uint8List? _safeDecodeB64(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    try {
      var v = s.trim();
      final comma = v.indexOf(',');
      if (comma != -1 &&
          v.substring(0, comma).toLowerCase().contains('base64')) {
        v = v.substring(comma + 1);
      }
      v = v.replaceAll(RegExp(r'\s'), '');
      if (v.toLowerCase() == 'string' || v.startsWith('<base64:')) return null;
      return base64Decode(base64.normalize(v));
    } catch (_) {
      return null;
    }
  }

  String _displayPhone(model.Customer c) {
    try {
      if (c.phone.isNotEmpty) return c.phone;
    } catch (_) {}
    try {
      final m = c.toMap();
      final p = (m['PhoneNumber'] ?? m['phone'] ?? m['Phone'] ?? '').toString();
      return p;
    } catch (_) {}
    return '';
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? avatar;

    if (avatarUrlOverride != null && _looksLikeUrl(avatarUrlOverride)) {
      avatar = NetworkImage(avatarUrlOverride!);
    }
    if (avatar == null &&
        customer.imageBytes != null &&
        customer.imageBytes!.isNotEmpty) {
      avatar = MemoryImage(customer.imageBytes!);
    }
    if (avatar == null && (customer.imageB64 ?? '').isNotEmpty) {
      final bytes = _safeDecodeB64(customer.imageB64);
      if (bytes != null && bytes.isNotEmpty) avatar = MemoryImage(bytes);
    }
    if (avatar == null && _looksLikeUrl(customer.others)) {
      avatar = NetworkImage(customer.others!);
    }

    return GestureDetector(
      onTap: onTap,
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
              backgroundColor: Colors.pink.shade50,
              foregroundImage: avatar,
              child: avatar == null
                  ? Text(
                      (customer.surname.isNotEmpty
                              ? customer.surname[0]
                              : customer.name.isNotEmpty
                              ? customer.name[0]
                              : '?')
                          .toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.pink,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.surname,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    customer.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black54,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _displayPhone(customer),
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Simple two-button switch bar used by both pages
class _EventSwitchBar extends StatelessWidget {
  final bool
  showAnniversaries; // true => Anniversaries selected, false => Birthdays selected
  final VoidCallback onBirthdaysTap;
  final VoidCallback onAnniversariesTap;

  const _EventSwitchBar({
    required this.showAnniversaries,
    required this.onBirthdaysTap,
    required this.onAnniversariesTap,
  });

  @override
  Widget build(BuildContext context) {
    final selectedStyle = ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF38B6E4),
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 0,
      padding: const EdgeInsets.symmetric(vertical: 10),
    );

    final unselectedStyle = OutlinedButton.styleFrom(
      foregroundColor: Colors.grey.shade700,
      side: BorderSide(color: Colors.grey.shade300),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(vertical: 10),
    );

    return Row(
      children: [
        Expanded(
          child: showAnniversaries
              ? OutlinedButton.icon(
                  onPressed: onBirthdaysTap,
                  icon: const Icon(Icons.cake_outlined),
                  label: const Text('Birthdays'),
                  style: unselectedStyle,
                )
              : ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.cake),
                  label: const Text('Birthdays'),
                  style: selectedStyle,
                ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: showAnniversaries
              ? ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.favorite),
                  label: const Text('Anniversaries'),
                  style: selectedStyle,
                )
              : OutlinedButton.icon(
                  onPressed: onAnniversariesTap,
                  icon: const Icon(Icons.favorite_border),
                  label: const Text('Anniversaries'),
                  style: unselectedStyle,
                ),
        ),
      ],
    );
  }
}
