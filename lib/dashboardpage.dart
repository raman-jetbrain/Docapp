import 'dart:convert';

import 'package:docapp/anniversaryevent.dart';
import 'package:docapp/birthdaylist.dart';
import 'package:docapp/login/Loginpage.dart';
import 'package:docapp/customerpage.dart';
import 'package:docapp/model/customer.dart' as model;
import 'package:docapp/pages/adduserpage%20.dart';
import 'package:docapp/utils/wish_tracker.dart';
import 'package:docapp/postereditpage.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

// Use same avatar widget as on Family page
import 'package:docapp/utils/famildetailsutility.dart';

// Shared customer API service (wraps /GetAllAsync and /GetAsync)
import 'package:docapp/api/customer_api_service.dart';

const kPrimaryBlue = Color(0xFF3B5998);

class Dashboardpage extends StatefulWidget {
  const Dashboardpage({super.key});

  @override
  State<Dashboardpage> createState() => _DashboardpageState();
}

class TodayEventModel {
  final model.Customer customer;
  final String name;   // first name only
  final String type;   // 'Birthday' or 'Anniversary'
  final String date;   // dd MMM
  final String phone;
  final bool isDone;   // used by WishTracker only

  TodayEventModel({
    required this.customer,
    required this.name,
    required this.type,
    required this.date,
    required this.phone,
    required this.isDone,
  });
}

class _DashboardpageState extends State<Dashboardpage> {
  final CustomerApiService _api = CustomerApiService();

  /// Total from /api/CustomerDataM/GetAsync (all records)
  int _customerCount = 0;

  /// Listed/parent count from getCustomers() (GetAllAsync filtered)
  int _listedCustomerCount = 0;

  int _birthdayCount = 0;
  int _anniversaryCount = 0;
  List<TodayEventModel> _todaysEvents = [];
  bool _isLoading = false;
  String? _error;

  /// Parents only, used for events & birthday/anniversary stats
  List<model.Customer> _allCustomers = [];

  static const List<String> _dobKeys = [
    'DOB',
    'dob',
    'dateOfBirth',
    'birthdate',
    'BirthDate',
  ];
  static const List<String> _annivKeys = [
    'MarriedDate',
    'marriedDate',
    'anniversary',
    'wedding_anniversary',
    'marriageDate',
  ];

  @override
  void initState() {
    super.initState();
    _loadCachedCounts();  // get last known listed count from CustomerScreen
    _loadFromApi();
  }

  Future<void> _loadCachedCounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final listed = prefs.getInt('listed_customer_count');
      if (mounted && listed != null) {
        setState(() {
          _listedCustomerCount = listed;
        });
      }
    } catch (_) {
      // ignore cache errors
    }
  }

  // ---------------- Load + compute today's events ----------------

  Future<void> _loadFromApi() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 1) Get ALL records via /GetAsync (for total count)
      // 2) Get listed/parent records via GetAllAsync (via getCustomers)
      final results = await Future.wait([
        _api.getCustomersFromGetAsync(), // -> /api/CustomerDataM/GetAsync
        _api.getCustomers(),            // -> /GetAllAsync (parents only)
      ]);

      final allRecords = results[0];
      final parents    = results[1];

      if (!mounted) return;

      setState(() {
        _customerCount        = allRecords.length; // count from GetAsync
        _listedCustomerCount  = parents.length;    // parents only
        _allCustomers         = parents;
      });

      // Compute today's events and birthday/anniversary counts using parents
      await _computeToday(parents);

      // Optional cache: cache only parents and update listed count cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('listed_customer_count', parents.length);

      final safeList = parents.map((c) {
        final m = c.toMap();
        m.remove('imageBytes');
        m.remove('imageB64');
        return m;
      }).toList();
      await prefs.setString('dashboard_customers', json.encode(safeList));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _computeToday(List<model.Customer> customers) async {
    final now = DateTime.now();
    final List<TodayEventModel> events = [];
    int bCount = 0;
    int aCount = 0;

    for (final c in customers) {
      final rawName = (c.name).toString().trim();
      final firstName =
          rawName.isNotEmpty ? rawName.split(' ').first : '';
      final displayName =
          firstName.isNotEmpty ? firstName : 'Unknown';

      final phone = _customerPhone(c);

      // Birthday
      final bday = _birthdayOf(c);
      if (_isSameMonthDay(bday, now)) {
        bCount++;
        final done =
            await WishTracker.isDone(phone: phone, type: 'birthday');

        events.add(
          TodayEventModel(
            customer: c,
            name: displayName,
            type: 'Birthday',
            date: bday != null ? DateFormat('dd MMM').format(bday) : '',
            phone: phone,
            isDone: done,
          ),
        );
      }

      // Anniversary
      final anniv = _anniversaryOf(c);
      if (_isSameMonthDay(anniv, now)) {
        aCount++;
        final done =
            await WishTracker.isDone(phone: phone, type: 'anniversary');

        events.add(
          TodayEventModel(
            customer: c,
            name: displayName,
            type: 'Anniversary',
            date: anniv != null ? DateFormat('dd MMM').format(anniv) : '',
            phone: phone,
            isDone: done,
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        _birthdayCount     = bCount;
        _anniversaryCount  = aCount;
        _todaysEvents      = events;
      });
    }
  }

  // ---------------- Helpers ----------------

  String _normalizePhoneStr(String s) {
    var digits = s.replaceAll(RegExp(r'\D'), '');
    digits = digits.replaceFirst(RegExp(r'^0+'), '');
    if (digits.length > 10) {
      digits = digits.substring(digits.length - 10);
    }
    return digits;
  }

  String _customerPhone(model.Customer c) {
    String phone = '';
    try {
      phone = (c.phone).toString().trim();
    } catch (_) {
      final m = c.toMap();
      phone = (m['PhoneNumber'] ??
                  m['phone'] ??
                  m['Phone'] ??
                  m['mobile'] ??
                  m['Mobile'] ??
                  '')
              .toString()
              .trim();
    }
    return phone;
  }

  DateTime? _birthdayOf(model.Customer c) {
    final m = c.toMap();
    for (final k in _dobKeys) {
      if (m.containsKey(k) && m[k] != null) {
        final dt = _parseDate(m[k]);
        if (dt != null) return dt;
      }
    }
    try {
      if ((c.dob ?? '').isNotEmpty) {
        final dt = DateTime.tryParse(c.dob);
        if (dt != null) return dt;
      }
    } catch (_) {}
    return null;
  }

  DateTime? _anniversaryOf(model.Customer c) {
    final status = (c.maritalStatus ?? c.toMap()['MaritalStatus'] ?? '')
        .toString()
        .toLowerCase();
    if (status.isNotEmpty && status != 'married') return null;

    final m = c.toMap();
    for (final k in _annivKeys) {
      if (m.containsKey(k) && m[k] != null) {
        final dt = _parseDate(m[k]);
        if (dt != null) return dt;
      }
    }
    try {
      if ((c.marriedDate ?? '').isNotEmpty) {
        final dt = DateTime.tryParse(c.marriedDate!);
        if (dt != null) return dt;
      }
    } catch (_) {}
    return null;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {}
    final norm = s.replaceAll('/', '-');
    final parts = norm.split('-');
    if (parts.length == 3) {
      int? d = int.tryParse(parts[0]);
      int? m = int.tryParse(parts[1]);
      int? y = int.tryParse(parts[2]);
      if (y != null && m != null && d != null) {
        return DateTime(y, m, d);
      }
    }
    return null;
  }

  bool _isSameMonthDay(DateTime? dt, DateTime on) {
    if (dt == null) return false;
    if (dt.month == 2 && dt.day == 29) {
      final isLeap = (on.year % 400 == 0) ||
          (on.year % 4 == 0 && on.year % 100 != 0);
      return on.month == 2 && (on.day == 29 || (!isLeap && on.day == 28));
    }
    return dt.month == on.month && dt.day == on.day;
  }

  // ---------------- Navigation & Logic ----------------
  Future<void> _openPosterForEvent(TodayEventModel event) async {
    final target = event.customer;

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PosterSharePage(
          customer: target,
          shareMessage: '',
        ),
      ),
    );

    if (result == true) {
      final isBirthday = event.type.toLowerCase().contains('birthday');
      final typeKey = isBirthday ? 'birthday' : 'anniversary';

      await WishTracker.markDone(
        phone: _customerPhone(target),
        type: typeKey,
      );

      if (mounted) await _loadFromApi();
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(120),
        child: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage("assets/images/Background2.jpeg"),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset(
                              "assets/images/logo2.png",
                              height: 60,
                              width: 90,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 15),
                          const Expanded(
                            child: Text(
                              'Maruthi \nInsure care,',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh, color: Colors.white),
                            onPressed: _loadFromApi,
                          ),
                          IconButton(
                            icon: const Icon(Icons.logout, color: Colors.white),
                            onPressed: _handleLogout,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _isLoading && _todaysEvents.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadFromApi,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 30),
                      _buildQuickActionsSection(),
                      const SizedBox(height: 30),
                      _buildCustomerStatsSection(),
                      const SizedBox(height: 30),
                      _buildTodayEventsSection(),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildCustomerStatsSection() {
    // Overall total = total from GetAsync + listed/parents count
    final int overallTotal = _customerCount + _listedCustomerCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Customer Stats',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: kPrimaryBlue,
          ),
        ),
        const SizedBox(height: 15),
        Container(
          height: 180,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 15,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: Row(
            children: [
              // TOTAL & breakdown
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black.withOpacity(0.7),
                      ),
                    ),
                    Text(
                      '$overallTotal', // overall total number
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: kPrimaryBlue,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
              Container(width: 1, height: 100, color: Colors.grey[300]),
              // BIRTHDAY COUNT
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'birthday',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black.withOpacity(0.7),
                      ),
                    ),
                    const Icon(Icons.cake,
                        color: Colors.pinkAccent, size: 28),
                    Text(
                      '$_birthdayCount',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.pinkAccent,
                      ),
                    ),
                  ],
                ),
              ),
              // ANNIVERSARY COUNT
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Anniversary',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black.withOpacity(0.7),
                      ),
                    ),
                    const Icon(Icons.favorite,
                        color: Colors.orangeAccent, size: 28),
                    Text(
                      '$_anniversaryCount',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.orangeAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- TODAY'S EVENTS ---
  Widget _buildTodayEventsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Today's Events",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: kPrimaryBlue,
              ),
            ),
            Text(
              DateFormat('MMM dd, yyyy').format(DateTime.now()),
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ],
        ),
        const SizedBox(height: 15),
        if (_todaysEvents.isNotEmpty)
          SizedBox(
            height: 140,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _todaysEvents.length,
              itemBuilder: (context, index) {
                final event = _todaysEvents[index];
                final isBirthday = event.type == 'Birthday';

                return InkWell(
                  borderRadius: BorderRadius.circular(15),
                  onTap: () {
                    if (isBirthday) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const BirthdayPage(),
                        ),
                      );
                    } else {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AnniversaryPage(),
                        ),
                      );
                    }
                  },
                  child: Container(
                    width: 130,
                    margin: const EdgeInsets.only(
                      right: 15,
                      bottom: 10,
                      top: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // PROFILE IMAGE using same logic as Family page
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isBirthday
                                  ? Colors.pinkAccent
                                  : Colors.orangeAccent,
                              width: 2,
                            ),
                          ),
                          child: CustomerAvatar(
                            customer: event.customer,
                            radius: 26,
                            bgColor: Colors.grey[100]!,
                            iconColor: isBirthday
                                ? Colors.pinkAccent
                                : Colors.orangeAccent,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // NAME: first name only (no surname)
                        Text(
                          event.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          event.type,
                          style: TextStyle(
                            fontSize: 12,
                            color: isBirthday
                                ? Colors.pink
                                : Colors.orange[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  // --- Other widgets ---

  Widget _buildQuickActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: kPrimaryBlue,
          ),
        ),
        const SizedBox(height: 15),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: _buildActionButton(
                'Add Customer',
                Icons.person_add_alt_1_rounded,
                _navigateToAddUserPage,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: _buildActionButton(
                'View All',
                Icons.people_alt,
                _navigateToCustomerScreen,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton(
      String title, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: kPrimaryBlue,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: kPrimaryBlue.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 5),
            )
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: Colors.white),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
            )
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavBarItem(Icons.home, 'Home', true, null),
            _buildNavBarItem(
              Icons.group,
              'Customers',
              false,
              _navigateToCustomerScreen,
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
              false,
              _navigateEventsPage,
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
    VoidCallback? onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: isSelected ? kPrimaryBlue : Colors.grey[400]),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isSelected ? kPrimaryBlue : Colors.grey[400],
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToCustomerScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CustomerScreen()),
    );
    if (mounted) _loadFromApi();
  }

  Future<void> _navigateEventsPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AnniversaryPage()),
    );
    if (mounted) _loadFromApi();
  }

  Future<void> _navigateToAddUserPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddNewUserPage()),
    );
    if (mounted) _loadFromApi();
  }

  Future<void> _handleLogout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => LoginView()),
      (route) => false,
    );
  }
}