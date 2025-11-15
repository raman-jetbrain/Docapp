import 'dart:convert';
import 'dart:typed_data';
import 'package:docapp/api/customer_api_service.dart';
import 'package:docapp/birthdaylist.dart';
import 'package:docapp/pages/adduserpage%20.dart';
import 'package:docapp/pages/customerdetailpage.dart';
import 'package:docapp/dashboardpage.dart' hide CustomerApiService;
import 'package:docapp/documentspage.dart';
import 'package:docapp/model/customer.dart' as model;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLastCustomer() async {
    final prefs = await SharedPreferences.getInstance();
    final String? userJson = prefs.getString('last_user');
    if (userJson != null) {
      final Map<String, dynamic> userMap = Map<String, dynamic>.from(
        json.decode(userJson),
      );
      if (!mounted) return;
      setState(() => lastCustomer = model.Customer.fromMap(userMap));
    }
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final fresh = await _api.getCustomers();

      setState(() {
        customers
          ..clear()
          ..addAll(fresh);
        if (lastCustomer == null && customers.isNotEmpty) {
          lastCustomer = customers.first;
        }
      });

      // Save metadata (strip images/b64 to keep storage small)
      final prefs = await SharedPreferences.getInstance();
      final safeList = customers.map((c) {
        final m = c.toMap();
        m.remove('imageBytes');
        m.remove('imageB64');
        return m;
      }).toList();
      await prefs.setString('customers', json.encode(safeList));

      // Background: fetch bytes via FileId if GET did not include real FileData
      Future.microtask(() async {
        try {
          final need = customers.where((c) {
            final hasBytes = c.imageBytes != null && c.imageBytes!.isNotEmpty;
            final hasUrl = (c.others ?? '').startsWith('http');
            final fid = c.fileId is int
                ? c.fileId as int
                : int.tryParse(c.fileId?.toString() ?? '');
            return !hasBytes && !hasUrl && fid != null && fid > 0;
          }).toList();

          if (need.isEmpty) return;

          final updated = List<model.Customer>.from(customers);

          // Sequential (simple, safe)
          for (final c in need) {
            try {
              final bytes = await _api.fetchFileBytesById(c.fileId);
              if (bytes != null && bytes.isNotEmpty) {
                final idx = updated.indexWhere((x) => x.phone == c.phone);
                if (idx != -1) {
                  final m = updated[idx].toMap();
                  m['imageBytes'] = bytes;
                  m['imageB64'] = null;
                  updated[idx] = model.Customer.fromMap(m);
                }
              }
            } catch (e, st) {
              debugPrint('[UI] fileId fetch failed for ${c.fileId}: $e\n$st');
            }
          }

          if (!mounted) return;

          final anyImproved = updated.any(
            (c) => c.imageBytes != null && c.imageBytes!.isNotEmpty,
          );
          if (anyImproved) {
            setState(() {
              customers
                ..clear()
                ..addAll(updated);
              if (lastCustomer != null) {
                final idx = customers.indexWhere(
                  (x) => x.phone == lastCustomer!.phone,
                );
                if (idx != -1) lastCustomer = customers[idx];
              }
              _filterCustomers();
            });
          }
        } catch (e, st) {
          debugPrint('[UI] background image hydration failed: $e\n$st');
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _filterCustomers();
      }
    }
  }

  void _filterCustomers() {
    final q = _searchController.text.trim().toLowerCase();

    if (q.isEmpty) {
      setState(() => filteredCustomers = List.of(customers));
      return;
    }

    final looksNumeric = RegExp(r'^[\d\s+\-()]+$').hasMatch(q);

    bool matchesRelatives(model.Customer c, String q) {
      try {
        final m = c.toMap();
        const relativeKeys = <String>[
          'parentName',
          'fatherName',
          'motherName',
          'guardianName',
          'spouseName',
          'husbandName',
          'wifeName',
          'childName',
          'child',
          'children',
          'childrenNames',
          'kids',
          'dependents',
          'dob',
          'DOB',
          'dateOfBirth',
          'DateOfBirth',
          'birthDate',
          'BirthDate',
          'birthday',
          'Birthday',
        ];

        for (final key in relativeKeys) {
          if (!m.containsKey(key) || m[key] == null) continue;
          final v = m[key];

          if (v is String) {
            if (v.toLowerCase().contains(q)) return true;
          } else if (v is List) {
            for (final e in v) {
              if (e == null) continue;
              if (e.toString().toLowerCase().contains(q)) return true;
            }
          } else {
            if (v.toString().toLowerCase().contains(q)) return true;
          }
        }
      } catch (_) {}
      return false;
    }

    final List<model.Customer> directMatches = customers.where((c) {
      final name = c.name.toLowerCase();
      final surname = c.surname.toLowerCase();
      final phone = c.phone.toLowerCase();

      final byNameOrSurname = name.contains(q) || surname.contains(q);
      final byRelatives = matchesRelatives(c, q);
      final byPhone = phone.contains(q);

      return byNameOrSurname || byRelatives || byPhone;
    }).toList();

    final Set<String> surnamesToInclude = {
      ...directMatches.map((c) => c.surname.toLowerCase()),
      ...customers
          .where((c) => c.surname.toLowerCase().contains(q))
          .map((c) => c.surname.toLowerCase()),
    };

    List<model.Customer> result;
    if (!looksNumeric && surnamesToInclude.isNotEmpty) {
      final family = customers.where(
        (c) => surnamesToInclude.contains(c.surname.toLowerCase()),
      );

      final seen = <String>{};
      final combined = <model.Customer>[];

      void add(model.Customer c) {
        final key = c.phone;
        if (seen.add(key)) combined.add(c);
      }

      for (final c in directMatches) {
        add(c);
      }
      for (final c in family) {
        add(c);
      }

      result = combined;
    } else {
      result = directMatches;
    }

    setState(() => filteredCustomers = result);
  }

  Future<void> _navigateToAddUserPage() async {
    final newUser = await Navigator.push<model.Customer>(
      context,
      MaterialPageRoute(builder: (context) => const AddNewUserPage()),
    );
    if (!mounted) return;

    if (newUser != null) {
      setState(() {
        lastCustomer = newUser;
        customers.insert(0, newUser);
        _filterCustomers();
      });

      final prefs = await SharedPreferences.getInstance();
      final lastUserMap = newUser.toMap()
        ..remove('imageBytes')
        ..remove('imageB64');
      await prefs.setString('last_user', json.encode(lastUserMap));

      final safeList = customers.map((c) {
        final m = c.toMap();
        m.remove('imageBytes');
        m.remove('imageB64');
        return m;
      }).toList();
      await prefs.setString('customers', json.encode(safeList));
    }
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
      MaterialPageRoute(builder: (_) => const BirthdayPage()),
    );
  }

  Future<void> _openCustomerDetail(model.Customer baseCustomer) async {
    // Try to fetch full details by id before navigating
    final baseMap = baseCustomer.toMap();
    final id = (baseMap['serverId'] ?? baseMap['id'] ?? '').toString();
    model.Customer detailed = baseCustomer;

    if (id.isNotEmpty) {
      // small loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      try {
        final fetched = await _api.getCustomerById(id);
        if (fetched != null) detailed = fetched;
      } catch (e) {
        debugPrint('[UI] getCustomerById($id) failed: $e');
      } finally {
        if (mounted) Navigator.of(context).pop(); // close dialog
      }
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerDetailPage(customer: detailed),
      ),
    );
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
          SliverAppBar(
            expandedHeight: 70,
            pinned: true,
            backgroundColor: Colors.transparent,
            leading: Navigator.canPop(context)
                ? const BackButton(color: Colors.white)
                : const SizedBox.shrink(),
            centerTitle: true,
            title: const Text(
              "Customers",
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

          SliverFillRemaining(
            child: Column(
              children: [
                // Search bar
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: padding,
                    vertical: 15,
                  ),
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
                        hintText: "Search by name, surname, phone or birthday",
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ),

                if (_isLoading)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 64,
                              color: Colors.redAccent,
                            ),
                            const SizedBox(height: 12),
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _loadCustomers,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _loadCustomers,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
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
                                onTap: () => _openCustomerDetail(lastCustomer!),
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
                          ...filteredCustomers.map((customer) {
                            if (lastCustomer != null &&
                                customer.phone == lastCustomer!.phone) {
                              return const SizedBox.shrink();
                            }
                            return CustomerCard(
                              customer: customer,
                              onTap: () => _openCustomerDetail(customer),
                              onDocumentsTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        DocumentsPage(customer: customer),
                                  ),
                                );
                              },
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

class CustomerCard extends StatelessWidget {
  final model.Customer customer;
  final VoidCallback? onTap;
  final VoidCallback? onDocumentsTap;

  const CustomerCard({
    super.key,
    required this.customer,
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

  // Parse various date formats into DateTime
  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;

    // .NET /Date(…)/ ticks (ms)
    final m = RegExp(r'^/Date\((\d+)\)/$').firstMatch(s);
    if (m != null) {
      final ms = int.tryParse(m.group(1)!);
      if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    }

    // ISO or general parseable format
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso.toLocal();

    // dd/MM/yyyy or MM/dd/yyyy or yyyy-MM-dd and common separators
    final parts = s.split(RegExp(r'[-/.\s]'));
    if (parts.length == 3) {
      int? a = int.tryParse(parts[0]);
      int? b = int.tryParse(parts[1]);
      int? c = int.tryParse(parts[2]);
      if (a != null && b != null && c != null) {
        // Guess: if first > 12 => dd/MM/yyyy else if second > 12 => MM/dd/yyyy
        if (a > 12) {
          return DateTime.tryParse('${c.toString().padLeft(4, '0')}-${b.toString().padLeft(2, '0')}-${a.toString().padLeft(2, '0')}');
        } else if (b > 12) {
          return DateTime.tryParse('${c.toString().padLeft(4, '0')}-${a.toString().padLeft(2, '0')}-${b.toString().padLeft(2, '0')}');
        } else {
          // fallback: assume yyyy-MM-dd if c is 4-digit year
          if (c > 1900) {
            return DateTime.tryParse('${a.toString().padLeft(4, '0')}-${b.toString().padLeft(2, '0')}-${c.toString().padLeft(2, '0')}');
          }
        }
      }
    }
    return null;
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
  }

  // Extract children/childName and DOB from the model’s map.
  List<String> _extractChildren(model.Customer c) {
    final out = <String>[];
    Map<String, dynamic> m;
    try {
      m = c.toMap();
    } catch (_) {
      m = {};
    }

    dynamic rawChildren =
        m['children'] ??
        m['Children'] ??
        m['childrenNames'] ??
        m['ChildrenNames'] ??
        m['kids'] ??
        m['Kids'] ??
        m['dependents'] ??
        m['Dependents'];

    dynamic rawSingle =
        m['childName'] ??
        m['ChildName'] ??
        m['child'] ??
        m['Child'];

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
        // Try JSON array text
        if ((s.startsWith('[') && s.endsWith(']')) ||
            (s.startsWith('"') && s.endsWith('"'))) {
          try {
            final decoded = json.decode(s);
            addFromDynamic(decoded);
            return;
          } catch (_) {}
        }
        // Split by common delimiters
        s.split(RegExp(r'[;,|]'))
            .map((x) => x.trim())
            .where((x) => x.isNotEmpty)
            .forEach(out.add);
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

  String? _extractBirthdayText(model.Customer c) {
    Map<String, dynamic> m;
    try {
      m = c.toMap();
    } catch (_) {
      m = {};
    }

    dynamic dobRaw =
        m['dob'] ??
        m['DOB'] ??
        m['DateOfBirth'] ??
        m['dateOfBirth'] ??
        m['BirthDate'] ??
        m['birthDate'] ??
        m['Birthday'] ??
        m['birthday'];

    DateTime? dob;
    if (dobRaw != null) {
      dob = _parseDate(dobRaw);
    }
    // If API stored ISO in 'dob', parse it
    if (dob == null && dobRaw is String) {
      final tryIso = DateTime.tryParse(dobRaw);
      if (tryIso != null) dob = tryIso.toLocal();
    }
    return dob != null ? _formatDate(dob) : null;
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? avatar;

    // 1) Prefer bytes from GET
    if (customer.imageBytes != null && customer.imageBytes!.isNotEmpty) {
      avatar = MemoryImage(customer.imageBytes!);
    }

    // 2) Base64 string
    if (avatar == null && (customer.imageB64 ?? '').isNotEmpty) {
      final bytes = _safeDecodeB64(customer.imageB64);
      if (bytes != null && bytes.isNotEmpty) avatar = MemoryImage(bytes);
    }

    // 3) URL
    if (avatar == null && _looksLikeUrl(customer.others)) {
      avatar = NetworkImage(customer.others!);
    }

    final children = _extractChildren(customer);
    final hasChildren = children.isNotEmpty;
    final childrenLabel = children.length > 1 ? 'Children' : 'Child';
    final childrenText = children.join(', ');

    final birthdayText = _extractBirthdayText(customer);

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
              child: avatar == null
                  ? const Icon(Icons.person, size: 30, color: Colors.blueGrey)
                  : null,
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Surname
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
                  // Name
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
                  // Phone
                  Text(
                    customer.phone,
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                    overflow: TextOverflow.ellipsis,
                  ),
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
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade800,
                              fontWeight: FontWeight.w500,
                            ),
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