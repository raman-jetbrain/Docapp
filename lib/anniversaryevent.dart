import 'dart:convert';
import 'dart:typed_data';

import 'package:docapp/birthdaylist.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:docapp/api/api_constant.dart';
import 'package:docapp/storage/Token_storage.dart';

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

  bool _isLoading = false;
  String? _error;

  List<model.Customer> _all = [];
  List<_CustomerWithAnniv> _matches = [];
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  // ---------------- API helpers ----------------

  String get _apiBaseNormalized {
    var b = ApiConstants.baseUrl.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    if (!b.toLowerCase().endsWith('/api')) b = '$b/api';
    return b;
  }

  /// Fetch all customers using /api/CustomerDataM/GetAllAsync
  Future<List<model.Customer>> _fetchCustomersFromApi() async {
    final token = await TokenStorage.getToken();

    final headers = <String, String>{
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    final uri = Uri.parse('$_apiBaseNormalized/CustomerDataM/GetAllAsync');

    final res = await http.get(uri, headers: headers);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final decoded = jsonDecode(res.body);

    dynamic payload = decoded;
    if (payload is Map && payload['Response'] != null) {
      payload = payload['Response'];
    }

    List list;
    if (payload is List) {
      list = payload;
    } else if (payload is Map && payload['Data'] is List) {
      list = payload['Data'];
    } else if (payload is Map && payload['data'] is List) {
      list = payload['data'];
    } else {
      throw Exception(
        'Unexpected response format from /CustomerDataM/GetAllAsync',
      );
    }

    final out = <model.Customer>[];

    for (final e in list) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);

      final Map<String, dynamic> effective =
          (m['CustomerData'] is Map)
              ? Map<String, dynamic>.from(m['CustomerData'])
              : m;

      final c = model.Customer.fromMap(effective);
      out.add(c);
    }

    return out;
  }

  // ---------------- Load + filter ----------------

  Future<void> _loadCustomers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final fresh = await _fetchCustomersFromApi();
      setState(() {
        _all = fresh;
      });
      _filterBySelectedDate();

      // Optional cache (without images)
      final prefs = await SharedPreferences.getInstance();
      final safeList = fresh.map((c) {
        final m = c.toMap();
        m.remove('imageBytes');
        m.remove('imageB64');
        return m;
      }).toList();
      await prefs.setString('anniversary_customers', json.encode(safeList));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshFromApi() => _loadCustomers();

  void _filterBySelectedDate() {
    final matches = _all
        .map((c) {
          final anniv = _getAnniversaryFromCustomer(c);
          return _CustomerWithAnniv(customer: c, anniversary: anniv);
        })
        .where((x) => _matchesMonthDay(x.anniversary, _selectedDate))
        .toList();

    // Sort by surname+name
    matches.sort((a, b) {
      final as = '${a.customer.surname} ${a.customer.name}'
          .toLowerCase()
          .trim();
      final bs = '${b.customer.surname} ${b.customer.name}'
          .toLowerCase()
          .trim();
      return as.compareTo(bs);
    });

    setState(() => _matches = matches);
  }

  /// Read anniversary from the Customer model:
  /// - maritalStatus (or MartialStatus/MaritalStatus in API) must be "Married"
  /// - marriedDate (MarriedDate) string must parse to a DateTime
  DateTime? _getAnniversaryFromCustomer(model.Customer c) {
    final status = (c.maritalStatus ?? '').toLowerCase();
    if (status != 'married') return null;

    final s = c.marriedDate;
    if (s == null || s.isEmpty) return null;

    // API gives "2010-10-11T06:30:00" -> parse directly
    final dt = DateTime.tryParse(s);
    return dt;
  }

  bool _isLeap(int y) {
    if (y % 400 == 0) return true;
    if (y % 100 == 0) return false;
    return y % 4 == 0;
  }

  bool _matchesMonthDay(DateTime? dt, DateTime on) {
    if (dt == null) return false;
    // special rule for Feb 29
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
      _filterBySelectedDate();
    }
  }

  // ---------------- Navigation helpers ----------------

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

  // ---------------- Build ----------------

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final padding = width * 0.05;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FC),
      body: RefreshIndicator(
        onRefresh: _refreshFromApi,
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
                    if (_isLoading && _all.isEmpty) {
                      return SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: const Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (_error != null && _all.isEmpty) {
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
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PosterSharePage(customer: e.customer, shareMessage: '',),
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
  final String? avatarUrl; // not used but kept for compatibility
  const _CustomerWithAnniv({
    required this.customer,
    required this.anniversary, this.avatarUrl,
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
      final p = (m['PhoneNumber'] ?? m['phone'] ?? m['Phone'] ?? '')
          .toString();
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
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey.shade700,
                    ),
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
  final bool showAnniversaries; // true => Anniversaries selected
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