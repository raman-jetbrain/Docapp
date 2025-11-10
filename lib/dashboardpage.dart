import 'dart:convert';
import 'package:docapp/CustomDrawerPage.dart';
import 'package:docapp/anniversaryevent.dart';
import 'package:docapp/api/customer_api_service.dart';
import 'package:docapp/api/description_api.dart';
import 'package:docapp/login/Loginpage.dart';
import 'package:docapp/customerpage.dart';
import 'package:docapp/dateventspage.dart';
import 'package:docapp/pages/adduserpage%20.dart';
import 'package:docapp/postereditpage.dart';
import 'package:docapp/birthdaylist.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kPrimaryBlue = Color(0xFF3B5998);

class Dashboardpage extends StatefulWidget {
  const Dashboardpage({super.key});

  

  @override
  State<Dashboardpage> createState() => _DashboardpageState();
}

class _DashboardpageState extends State<Dashboardpage> {
  int _customerCount = 0;
  int _birthdayCount = 0;
  int _anniversaryCount = 0;

  static const List<String> _dobKeys = [
    'dob',
    'DOB',
    'dateOfBirth',
    'birthdate',
    'birthDate',
    'date_of_birth',
    'birthday',
  ];
  static const List<String> _annivKeys = [
    'anniversary',
    'anniversaryDate',
    'wedding_anniversary',
    'doa',
    'dom',
    'dateOfAnniversary',
    'marriageDate',
  ];

  @override
  void initState() {
    super.initState();
    _loadCustomerData();
  }

  List<Map<String, dynamic>> _decodeCustomers(String jsonStr) {
    final List<Map<String, dynamic>> out = [];
    dynamic decoded;
    try {
      decoded = json.decode(jsonStr);
    } catch (e) {
      if (kDebugMode) debugPrint('[Dashboard] JSON decode error: $e');
      return out;
    }

    void addList(dynamic v) {
      if (v is List) {
        for (final e in v) {
          if (e is Map) out.add(Map<String, dynamic>.from(e));
        }
      }
    }

    if (decoded is List) {
      addList(decoded);
    } else if (decoded is Map) {
      final m = Map<String, dynamic>.from(decoded);
      final candidates = ['customers', 'data', 'items', 'list', 'result'];
      bool added = false;
      for (final k in candidates) {
        if (m[k] is List) {
          addList(m[k]);
          added = true;
          break;
        }
      }
      if (!added) {
        out.add(m);
      }
    }
    return out;
  }

  String? _toDateString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v.trim();
    if (v is int) return v.toString();
    if (v is double) return v.toInt().toString();
    if (v is Map) {
      final ms = v['milliseconds'] ?? v['millis'] ?? v['ms'];
      if (ms != null) return ms.toString();
      final sec = v['seconds'] ?? v['secs'] ?? v['s'];
      if (sec != null) {
        final s = int.tryParse(sec.toString());
        if (s != null) return (s * 1000).toString();
      }
    }
    return v.toString();
  }

  String? _firstDateByKeys(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k) && m[k] != null) {
        return _toDateString(m[k]);
      }
    }
    return null;
  }

  bool _isTodayMonthDay(String? raw) {
    final dt = _parseDateFlex(raw);
    if (dt == null) return false;
    final now = DateTime.now();
    return dt.day == now.day && dt.month == now.month;
  }

  DateTime? _parseDateFlex(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;

    if (RegExp(r'^\d+$').hasMatch(s)) {
      final n = int.tryParse(s);
      if (n != null) {
        if (s.length >= 12) return DateTime.fromMillisecondsSinceEpoch(n);
        if (s.length == 10)
          return DateTime.fromMillisecondsSinceEpoch(n * 1000);
      }
    }

    final iso = DateTime.tryParse(s);
    if (iso != null) return iso.isUtc ? iso.toLocal() : iso;

    final norm = s.replaceAll('/', '-').replaceAll('.', '-');
    final parts = norm.split('-').where((e) => e.trim().isNotEmpty).toList();

    if (parts.length >= 3) {
      if (parts[0].length == 4) {
        final y = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        final d = int.tryParse(parts[2]) ?? 0;
        if (y > 0 && m > 0 && d > 0) return DateTime(y, m, d);
      } else {
        final d = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        int y = int.tryParse(parts[2]) ?? 0;
        if (y > 0 && y < 100) y += 2000;
        if (y > 0 && m > 0 && d > 0) return DateTime(y, m, d);
      }
    }

    if (parts.length >= 2) {
      final now = DateTime.now();
      final d = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      if (m > 0 && d > 0) return DateTime(now.year, m, d);
    }

    final nums = RegExp(r'\d+').allMatches(s).map((m) => m.group(0)!).toList();
    if (nums.length >= 3 && nums[0].length == 4) {
      final y = int.tryParse(nums[0]) ?? 0;
      final m = int.tryParse(nums[1]) ?? 0;
      final d = int.tryParse(nums[2]) ?? 0;
      if (y > 0 && m > 0 && d > 0) return DateTime(y, m, d);
    } else if (nums.length >= 2) {
      final now = DateTime.now();
      final d = int.tryParse(nums[0]) ?? 0;
      final m = int.tryParse(nums[1]) ?? 0;
      if (m > 0 && d > 0) return DateTime(now.year, m, d);
    }

    return null;
  }

  var customer = CustomerApiService();

  Future<void> _loadCustomerData() async {
    final prefs = await SharedPreferences.getInstance();
    final customersJson = prefs.getString('customers');

    if (customersJson == null || customersJson.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _customerCount = 0;
          _birthdayCount = 0;
          _anniversaryCount = 0;
        });
      }
      if (kDebugMode) debugPrint('[Dashboard] No stored customers.');
      return;
    }

    final customers = _decodeCustomers(customersJson);

    int birthdayCount = 0;
    int anniversaryCount = 0;

    for (final m in customers) {
      final dob = _firstDateByKeys(m, _dobKeys);
      if (_isTodayMonthDay(dob)) birthdayCount++;

      final anniv = _firstDateByKeys(m, _annivKeys);
      if (_isTodayMonthDay(anniv)) anniversaryCount++;
    }

    if (mounted) {
      setState(() {
        _customerCount = customers.length;
        _birthdayCount = birthdayCount;
        _anniversaryCount = anniversaryCount;
      });
    }

    if (kDebugMode) {
      debugPrint(
        '[Dashboard] customers=$_customerCount birthdays=$_birthdayCount anniversaries=$_anniversaryCount',
      );
    }
  }

  Future<void> _navigateToCustomerScreen() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CustomerScreen()));
    if (mounted) _loadCustomerData();
  }

  Future<void> _navigateTodayEventsPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BirthdayPage()),
    );
    if (mounted) _loadCustomerData();
  }

  // Navigate to Anniversary poster page
  Future<void> _navigateEventsPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AnniversaryPage(),
      ), // no customer required
    );
    if (mounted) _loadCustomerData();
  }

  Future<void> _navigateToAddUserPage() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AddNewUserPage()));
    if (mounted) _loadCustomerData();
  }

  Future<void> _navigateToCustomerDrawerPage() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => AppDrawer()));
    if (mounted) _loadCustomerData();
  }

  Future<void> _handleLogout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
      await prefs.remove('refresh_token');
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => LoginView()),
      (route) => false,
    );
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
                              'Maruthi \nInsure care,',
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
            _buildNavBarItem(Icons.home, 'Home', true),
            _buildNavBarItem(Icons.group, 'Customers', false),
            _buildNavBarItem(Icons.add_circle, 'Add', false),
            _buildNavBarItem(Icons.notifications, 'Events', false),
            _buildNavBarItem(Icons.logout, 'Logout', false),
          ],
        ),
      ),
    );
  }

  Widget _buildNavBarItem(IconData icon, String label, bool isSelected) {
    final screenWidth = MediaQuery.of(context).size.width;
    final iconSize = screenWidth * 0.07;
    final fontSize = screenWidth * 0.03;

    return InkWell(
      onTap: () {
        if (label == 'Customers') {
          _navigateToCustomerScreen();
        } else if (label == 'Add') {
          _navigateToAddUserPage();
        } else if (label == 'Events') {
          _navigateEventsPage(); // go to Anniversary poster page
        } else if (label == 'Logout') {
          _handleLogout();
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

class Customer {
  // Core
  final String name;
  final String surname;
  final String phone;
  final String email;
  final String address;
  final String dob; // UI-friendly DOB text (not ISO) for your current screens
  final String gender;

  // Extras
  final List<Map<String, String>> customEntries;
  final String? others; // may contain data URL: data:image/png;base64,....
  final String? photo; // local photo path (if any)

  // Image handling
  final Uint8List? imageBytes; // in-memory bytes for immediate UI
  final String? imageB64; // base64 persisted in storage

  // IDs
  final String? id; // optional unified id (string), may mirror serverId
  final String? serverId; // server-side ID (string)
  final int? fileId; // FileId from server (int)
  final int? localId; // local auto-increment id (for caching only)

  Customer({
    required this.name,
    required this.surname,
    required this.phone,
    required this.email,
    required this.address,
    required this.dob,
    required this.gender,
    required this.customEntries,
    this.others,
    this.photo,
    this.imageBytes,
    this.imageB64,
    this.id,
    this.serverId,
    this.fileId,
    this.localId,
  });

  // -------- Helpers --------

  static String? _stringOrNull(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString());
  }

  static Uint8List? _decodeB64Image(dynamic v) {
    if (v == null) return null;
    var s = v.toString().trim();
    if (s.isEmpty) return null;

    // Allow data URLs: data:image/png;base64,xxxx
    final commaIndex = s.indexOf(',');
    if (commaIndex != -1 &&
        s.substring(0, commaIndex).toLowerCase().contains('base64')) {
      s = s.substring(commaIndex + 1);
    }

    // Remove whitespace/newlines
    s = s.replaceAll(RegExp(r'\s'), '');
    try {
      return base64Decode(base64.normalize(s));
    } catch (_) {
      return null;
    }
  }

  static List<Map<String, String>> _coerceCustomEntries(dynamic v) {
    if (v is List) {
      return v.map<Map<String, String>>((e) {
        if (e is Map) {
          return e.map(
            (k, val) => MapEntry(k.toString(), val?.toString() ?? ''),
          );
        }
        return <String, String>{};
      }).toList();
    }
    return <Map<String, String>>[];
  }

  // -------- Mapping --------

  factory Customer.fromMap(Map<String, dynamic> m) {
    // Resolve IDs
    final String? idStr = _stringOrNull(
      m['id'] ??
          m['Id'] ??
          m['ID'] ??
          m['CustomerId'] ??
          m['CustomerID'] ??
          m['CustomerDataMId'] ??
          m['CustomerDataMID'] ??
          m['CustomerDataId'] ??
          m['CustomerDataID'],
    );

    final String? serverId = _stringOrNull(
      m['serverId'] ?? m['ServerId'] ?? m['ServerID'] ?? idStr,
    );

    // Resolve FileId (if present)
    final dynamic httpFile = m['HttpFileData'] ?? m['httpFileData'];
    final int? fileId = _toInt(
      m['fileId'] ??
          m['FileId'] ??
          (httpFile is Map ? (httpFile['Id'] ?? httpFile['FileId']) : null),
    );

    // Resolve image bytes from multiple possible sources
    Uint8List? bytes;
    // 1) direct imageBytes (bytes or base64 string)
    final dynamic imgField = m['imageBytes'];
    if (imgField is Uint8List && imgField.isNotEmpty) {
      bytes = imgField;
    } else if (imgField is String && imgField.isNotEmpty) {
      bytes = _decodeB64Image(imgField);
    }

    // 2) imageB64 (base64 string)
    String? imageB64 = _stringOrNull(m['imageB64']);
    if (bytes == null && imageB64 != null) {
      bytes = _decodeB64Image(imageB64);
    }

    // 3) Others may contain a data URL
    final String? others = _stringOrNull(m['others'] ?? m['Others']);
    if (bytes == null && others != null && others.startsWith('data:image')) {
      bytes = _decodeB64Image(others);
    }

    // If we decoded bytes but had no imageB64, create one for persistence
    imageB64 ??= (bytes != null && bytes.isNotEmpty)
        ? base64Encode(bytes)
        : null;

    return Customer(
      name: _stringOrNull(m['name'] ?? m['Name']) ?? '',
      surname: _stringOrNull(m['surname'] ?? m['Surname']) ?? '',
      phone: _stringOrNull(m['phone'] ?? m['Phone'] ?? m['PhoneNumber']) ?? '',
      email: _stringOrNull(m['email'] ?? m['Email'] ?? m['EmailId']) ?? '',
      address: _stringOrNull(m['address'] ?? m['Address']) ?? '',
      dob: _stringOrNull(m['dob'] ?? m['DOB'] ?? m['SDOB']) ?? '',
      gender: _stringOrNull(m['gender'] ?? m['Gender']) ?? '',
      customEntries: _coerceCustomEntries(m['customEntries']),
      others: others,
      photo: _stringOrNull(m['photo']),
      imageBytes: bytes,
      imageB64: imageB64,
      id: idStr,
      serverId: serverId,
      fileId: fileId,
      localId: _toInt(m['localId']),
    );
  }

  Map<String, dynamic> toMap() {
    // Prefer to include imageB64 (safe for JSON). Avoid raw imageBytes in JSON.
    final String? outB64 =
        imageB64 ??
        (imageBytes != null && imageBytes!.isNotEmpty
            ? base64Encode(imageBytes!)
            : null);

    return <String, dynamic>{
      // IDs
      if (id != null) 'id': id,
      if (serverId != null) 'serverId': serverId,
      if (fileId != null) 'fileId': fileId,
      if (localId != null) 'localId': localId,

      // Core
      'name': name,
      'surname': surname,
      'phone': phone,
      'email': email,
      'address': address,
      'dob': dob,
      'gender': gender,

      // Extras
      'customEntries': customEntries,
      if (others != null) 'others': others,
      if (photo != null) 'photo': photo,

      // Image persistence
      if (outB64 != null) 'imageB64': outB64,
    };
  }

  Customer copyWith({
    String? name,
    String? surname,
    String? phone,
    String? email,
    String? address,
    String? dob,
    String? gender,
    List<Map<String, String>>? customEntries,
    String? others,
    String? photo,
    Uint8List? imageBytes,
    String? imageB64,
    String? id,
    String? serverId,
    int? fileId,
    int? localId,
  }) {
    return Customer(
      name: name ?? this.name,
      surname: surname ?? this.surname,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      dob: dob ?? this.dob,
      gender: gender ?? this.gender,
      customEntries: customEntries ?? this.customEntries,
      others: others ?? this.others,
      photo: photo ?? this.photo,
      imageBytes: imageBytes ?? this.imageBytes,
      imageB64: imageB64 ?? this.imageB64,
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      fileId: fileId ?? this.fileId,
      localId: localId ?? this.localId,
    );
  }
}
