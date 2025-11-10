import 'dart:convert';
import 'dart:typed_data';
import 'package:docapp/anniversaryevent.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:docapp/api/customer_api_service.dart';
import 'package:docapp/dashboardpage.dart';
import 'package:docapp/dateventspage.dart';
import 'package:docapp/pages/adduserpage%20.dart';
import 'package:docapp/pages/customerdetailpage.dart';
import 'package:docapp/documentspage.dart';
import 'package:docapp/model/customer.dart' as model;
import 'package:docapp/postereditpage.dart';

class BirthdayPage extends StatefulWidget {
  const BirthdayPage({super.key});

  @override
  State<BirthdayPage> createState() => _BirthdayPageState();
}

class _BirthdayPageState extends State<BirthdayPage> {
  static const Color kPrimaryBlue = Color(0xFF38B6E4);
  final CustomerApiService _api = CustomerApiService();

  bool _isLoading = false;
  String? _error;

  List<model.Customer> _all = [];
  List<_CustomerWithDob> _matches = [];
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final fresh = await _api.getCustomers();
      setState(() {
        _all = fresh;
      });
      _filterBySelectedDate();

      // Optional: persist safe cache
      final prefs = await SharedPreferences.getInstance();
      final safeList = fresh.map((c) {
        final m = c.toMap();
        m.remove('imageBytes');
        m.remove('imageB64');
        return m;
      }).toList();
      await prefs.setString('customers', json.encode(safeList));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterBySelectedDate() {
    final matches = _all.map((c) {
      final dob = _readDob(c.toMap());
      return _CustomerWithDob(customer: c, dob: dob);
    }).where((x) => _matchesMonthDay(x.dob, _selectedDate)).toList();

    setState(() => _matches = matches);
  }

  // Keys we accept for DOB
  static const List<String> _dobKeys = [
    'DOB','Dob','dob',
    'DateOfBirth','dateOfBirth',
    'BirthDate','birthDate',
    'Birthday','birthday',
    'date_of_birth',
  ];

  DateTime? _readDob(Map<String, dynamic> m) {
    // Try exact keys
    for (final k in _dobKeys) {
      if (m.containsKey(k) && m[k] != null) {
        final dt = _parseDateFlex(m[k]);
        if (dt != null) return dt;
      }
    }
    // Case-insensitive fallback
    final lower = {for (final e in m.entries) e.key.toLowerCase(): e.value};
    for (final k in _dobKeys) {
      final v = lower[k.toLowerCase()];
      if (v != null) {
        final dt = _parseDateFlex(v);
        if (dt != null) return dt;
      }
    }
    return null;
  }

  // Robust parsing
  DateTime? _parseDateFlex(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;

    final s0 = v.toString().trim();
    if (s0.isEmpty || s0.toLowerCase() == 'null') return null;

    // .NET /Date(ms)/
    final mNet = RegExp(r'^/Date\((\d+)\)/$').firstMatch(s0);
    if (mNet != null) {
      final ms = int.tryParse(mNet.group(1)!);
      if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    }

    // Digits only -> epoch sec/ms
    if (RegExp(r'^\d+$').hasMatch(s0)) {
      final n = int.tryParse(s0);
      if (n != null) {
        if (s0.length >= 12) return DateTime.fromMillisecondsSinceEpoch(n, isUtc: true).toLocal();
        if (s0.length == 10) return DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true).toLocal();
      }
    }

    // ISO
    final iso = DateTime.tryParse(s0);
    if (iso != null) return iso.isUtc ? iso.toLocal() : iso;

    // dd-MM-yyyy, dd/MM/yyyy, dd-MM
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
      // Treat 29 Feb as 28 Feb on non-leap years
      return on.month == 2 && (on.day == 29 || (!_isLeap(on.year) && on.day == 28));
    }
    return dt.month == on.month && dt.day == on.day;
  }

  String _formatDate(DateTime d, {bool includeYear = false}) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
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
      _filterBySelectedDate();
    }
  }

  // Navigation helpers
  void _navigateToDashboard() {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const Dashboardpage()));
  }

  void _navigateToCustomers() {
    Navigator.pop(context);
  }

  void _navigateToAddUserPage() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AddNewUserPage()));
  }

  void _navigateToEvents() {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AnniversaryPage()));
  }

  void _openAnniversaries() {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AnniversaryPage()));
  }

  Future<void> _openCustomerDetail(model.Customer baseCustomer) async {
    final baseMap = baseCustomer.toMap();
    final id = (baseMap['serverId'] ?? baseMap['id'] ?? '').toString();
    model.Customer detailed = baseCustomer;

    if (id.isNotEmpty) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      try {
        // If you have a details API, fetch here (optional)
        // final fetched = await _api.getCustomerById(id);
        // if (fetched != null) detailed = fetched;
      } catch (e) {
        debugPrint('[BirthdayPage] getCustomerById($id) failed: $e');
      } finally {
        if (mounted) Navigator.of(context).pop();
      }
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CustomerDetailPage(customer: detailed)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final padding = width * 0.05;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FC),
      body: RefreshIndicator(
        onRefresh: _loadCustomers,
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
                "Birthdays",
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
                  icon: const Icon(Icons.calendar_today_outlined, color: Colors.white),
                  onPressed: _pickDate,
                ),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: _loadCustomers,
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

            // Header block: with switch
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: padding, vertical: 12),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _EventSwitchBar(
                        showAnniversaries: false,
                        onBirthdaysTap: () {}, // already here
                        onAnniversariesTap: _openAnniversaries,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.cake_outlined, color: Colors.pink),
                          const SizedBox(width: 10),
                          Text(
                            'Birthdays on ${_formatDate(_selectedDate, includeYear: true)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setState(() => _selectedDate = DateTime.now());
                              _filterBySelectedDate();
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
                    if (_isLoading) {
                      return SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: const Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (_error != null) {
                      return SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: _loadCustomers,
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
                            'No birthdays on ${_formatDate(_selectedDate, includeYear: true)}',
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                        ),
                      );
                    }

                    return Column(
                      children: [
                        const SizedBox(height: 12),
                        ..._matches.map((cwe) => EventCustomerCard(
                              customer: cwe.customer,
                              subtitle: cwe.dob != null
                                  ? '🎂 ${_formatDate(cwe.dob!, includeYear: false)}'
                                  : null,
                              // On tap, open PosterSharePage directly
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => PosterSharePage(customer: cwe.customer),
                                  ),
                                );
                              },
                              onDocumentsTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DocumentsPage(customer: cwe.customer),
                                  ),
                                );
                              },
                            )),
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

  // Bottom nav UI; make Events go to Anniversaries
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
            _buildNavBarItem(Icons.group, 'Customers', false, _navigateToCustomers),
            _buildNavBarItem(Icons.add_circle, 'Add', false, _navigateToAddUserPage),
            _buildNavBarItem(Icons.notifications, 'Events', true, _navigateToEvents),
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
          Icon(icon, color: isSelected ? kPrimaryBlue : Colors.grey[400], size: iconSize),
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

class _CustomerWithDob {
  final model.Customer customer;
  final DateTime? dob;
  const _CustomerWithDob({required this.customer, required this.dob});
}

// Card UI (same style as Anniversary card)
class EventCustomerCard extends StatelessWidget {
  final model.Customer customer;
  final String? subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onDocumentsTap;

  const EventCustomerCard({
    super.key,
    required this.customer,
    this.subtitle,
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
      if (comma != -1 && v.substring(0, comma).toLowerCase().contains('base64')) {
        v = v.substring(comma + 1);
      }
      v = v.replaceAll(RegExp(r'\s'), '');
      if (v.toLowerCase() == 'string' || v.startsWith('<base64:')) return null;
      return base64Decode(base64.normalize(v));
    } catch (_) {
      return null;
    }
  }

  List<String> _extractChildren(model.Customer c) {
    final out = <String>[];
    Map<String, dynamic> m;
    try {
      m = c.toMap();
    } catch (_) {
      m = {};
    }

    dynamic rawChildren =
        m['children'] ?? m['Children'] ?? m['childrenNames'] ?? m['ChildrenNames'] ??
        m['kids'] ?? m['Kids'] ?? m['dependents'] ?? m['Dependents'];

    dynamic rawSingle = m['childName'] ?? m['ChildName'] ?? m['child'] ?? m['Child'];

    void addFromDynamic(dynamic v) {
      if (v == null) return;
      if (v is List) {
        for (final e in v) {
          final s = e?.toString().trim();
          if (s != null && s.isNotEmpty) out.add(s);
        }
      } else if (v is String) {
        final s = v.trim();
        if (s.isEmpty) return;
        if ((s.startsWith('[') && s.endsWith(']')) || (s.startsWith('"') && s.endsWith('"'))) {
          try {
            final decoded = json.decode(s);
            addFromDynamic(decoded);
            return;
          } catch (_) {}
        }
        s.split(RegExp(r'[;,|]')).map((x) => x.trim()).where((x) => x.isNotEmpty).forEach(out.add);
      } else {
        final s = v.toString().trim();
        if (s.isNotEmpty) out.add(s);
      }
    }

    addFromDynamic(rawChildren);
    addFromDynamic(rawSingle);

    final seen = <String>{};
    return out.where((e) => seen.add(e)).toList();
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? avatar;

    if (customer.imageBytes != null && customer.imageBytes!.isNotEmpty) {
      avatar = MemoryImage(customer.imageBytes!);
    }
    if (avatar == null && (customer.imageB64 ?? '').isNotEmpty) {
      final bytes = _safeDecodeB64(customer.imageB64);
      if (bytes != null && bytes.isNotEmpty) avatar = MemoryImage(bytes);
    }
    if (avatar == null && _looksLikeUrl(customer.others)) {
      avatar = NetworkImage(customer.others!);
    }

    final children = _extractChildren(customer);
    final hasChildren = children.isNotEmpty;
    final childrenLabel = children.length > 1 ? 'Children' : 'Child';
    final childrenText = children.join(', ');

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
              backgroundColor: Colors.blue.shade50,
              backgroundImage: avatar,
              child: avatar == null ? const Icon(Icons.person, size: 30, color: Colors.blueGrey) : null,
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Surname
                  Text(
                    customer.surname,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Name
                  Text(
                    customer.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black54),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // Phone
                  Text(
                    customer.phone,
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle!,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (hasChildren) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.child_care, size: 18, color: Colors.orange),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '$childrenLabel: $childrenText',
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade800, fontWeight: FontWeight.w500),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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
  final bool showAnniversaries; // true => Anniversaries selected, false => Birthdays selected
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