import 'dart:convert';
import 'package:docapp/CustomDrawerPage.dart';
import 'package:docapp/adduserpage%20.dart';
import 'package:docapp/api/api_constant.dart';
import 'package:docapp/customerpage.dart';
import 'package:docapp/dateventspage.dart';
import 'package:docapp/model/customer.dart' as model;
import 'package:docapp/storage/Token_storage.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
    if (headers != null) debugPrint('[HTTP] Headers: ${jsonEncode(headers)}');
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

    // Your API uses "Response"
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

  // Map exact keys from your payload + optional base64 image
  model.Customer _mapApiToCustomer(Map<String, dynamic> m) {
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
        } catch (_) {
          // ignore invalid base64
        }
      }
    }

    // If you have DOB in API, add it here and to your model
    // final dob = (m['DOB'] ?? m['DateOfBirth'] ?? '').toString().trim();

    return model.Customer.fromMap({
      'name': first,
      'surname': last,
      'phone': phone,
      'email': email,
      'address': address,
      'gender': gender,
      'others': others,
      'imageBytes': bytes, // null unless FileData provided
      // 'dob': dob, // enable if your model supports it
    });
  }
}
// Colors
const kPrimaryBlue = Color(0xFF3B5998);

class Dashboardpage extends StatefulWidget {
  const Dashboardpage({super.key});

  @override
  State<Dashboardpage> createState() => _DashboardpageState();
}

class _DashboardpageState extends State<Dashboardpage> {
  int _customerCount = 0;
  int _birthdayCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCustomerData();
  }

  Future<void> _loadCustomerData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? customersJson = prefs.getString('customers');
    if (customersJson != null) {
      final List<dynamic> customersList = json.decode(customersJson);

      int birthdayCount = 0;
      final now = DateTime.now();

      for (var customerMap in customersList) {
        final dobString = customerMap['dob'] as String? ?? '';
        if (dobString.isNotEmpty) {
          try {
            final parts = dobString.split('/');
            if (parts.length >= 2) {
              final day = int.parse(parts[0]);
              final month = int.parse(parts[1]);
              if (day == now.day && month == now.month) {
                birthdayCount++;
              }
            }
          } catch (_) {}
        }
      }

      if (mounted) {
        setState(() {
          _customerCount = customersList.length;
          _birthdayCount = birthdayCount;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _customerCount = 0;
          _birthdayCount = 0;
        });
      }
    }
  }

  Future<void> _navigateToCustomerScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CustomerScreen()),
    );
    if (mounted) {
      _loadCustomerData();
    }
  }

  Future<void> _navigateTodayEventsPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DayEventsPage()),
    );
    if (mounted) {
      _loadCustomerData();
    }
  }

  Future<void> _navigateToAddUserPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddNewUserPage()),
    );
    if (mounted) {
      _loadCustomerData();
    }
  }

  Future<void> _navigateToCustomerDrawerPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) =>  AppDrawer()),
    );
    if (mounted) {
      _loadCustomerData();
    }
  }

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
              // Background Image
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
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
                              'Maruthi \nInsurance care,',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 30),
              _buildEventsSection(),
              const SizedBox(height: 30),
              _buildQuickActionsSection(),
              const SizedBox(height: 30),
              _buildCustomerStatsSection(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildEventsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Today's Events",
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
              child: _buildEventCard(
                " Birthday",
                '$_birthdayCount',
                Icons.cake,
                const Color(0xFFFCE1C2),
                () => _navigateTodayEventsPage(),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _buildEventCard(
                "Day Events",
                '$_birthdayCount', // placeholder
                Icons.event,
                const Color.fromARGB(255, 230, 255, 161),
                () => _navigateTodayEventsPage(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEventCard(
    String title,
    String count,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 150,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, size: 40, color: kPrimaryBlue),
            Text(
              count,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: Colors.black.withOpacity(0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

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
                () => _navigateToAddUserPage(),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: _buildActionButton(
                'View All',
                Icons.people_alt,
                () => _navigateToCustomerScreen(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton(String title, IconData icon, VoidCallback onTap) {
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
            ),
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

  Widget _buildCustomerStatsSection() {
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
              ),
            ],
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Total Customers',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '$_customerCount',
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: kPrimaryBlue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNavigationBar() {
    final screenWidth = MediaQuery.of(context).size.width;
    final navHeight = screenWidth * 0.18; // responsive height (~65–80px)

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
            _buildNavBarItem(Icons.home, 'Home', true),
            _buildNavBarItem(Icons.group, 'Customers', false),
            _buildNavBarItem(Icons.add_circle, 'Add', false),
            _buildNavBarItem(Icons.notifications, 'Events', false),
            _buildNavBarItem(Icons.menu, 'Menu', false),
          ],
        ),
      ),
    );
  }

  Widget _buildNavBarItem(IconData icon, String label, bool isSelected) {
    final screenWidth = MediaQuery.of(context).size.width;
    final iconSize = screenWidth * 0.07; // responsive icon (~26-32px)
    final fontSize = screenWidth * 0.03; // responsive text (~12px)

    return InkWell(
      onTap: () {
        if (label == 'Customers') {
          _navigateToCustomerScreen();
        } else if (label == 'Add') {
          _navigateToAddUserPage();
        } else if (label == 'Events') {
          _navigateTodayEventsPage();
        } else if (label == 'Menu') {
          _navigateToCustomerDrawerPage();
        }
      },
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