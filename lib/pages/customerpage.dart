import 'dart:convert';
import 'dart:typed_data';
import 'package:docapp/pages/adduserpage%20.dart';
import 'package:docapp/api/customer_api_service.dart';
import 'package:docapp/pages/customerdetailpage.dart';
import 'package:docapp/dashboardpage.dart';
import 'package:docapp/dateventspage.dart';
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
        final need = customers.where((c) {
          final hasBytes = c.imageBytes != null && c.imageBytes!.isNotEmpty;
          final hasUrl = (c.others ?? '').startsWith('http');
          final fid = c.fileId?.toString().trim();
          return !hasBytes && !hasUrl && (fid != null && fid.isNotEmpty);
        }).toList();
        if (need.isEmpty) return;

        final updated = List<model.Customer>.from(customers);
        const int kParallel = 3;
        final queue = List<model.Customer>.from(need);

        Future<void> worker() async {
          while (queue.isNotEmpty) {
            final c = queue.removeAt(0);
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
            } catch (e) {
              debugPrint('[UI] fileId fetch failed for ${c.fileId}: $e');
            }
          }
        }

        await Future.wait(List.generate(kParallel, (_) => worker()));
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
      MaterialPageRoute(builder: (_) => const DayEventsPage()),
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
                        hintText: "Search by name, surname or phone",
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
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => CustomerDetailPage(
                                        customer: lastCustomer!,
                                      ),
                                    ),
                                  );
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
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        CustomerDetailPage(customer: customer),
                                  ),
                                );
                              },
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
            _buildNavBarItem(Icons.menu, 'Menu', false, () {}),
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

  @override
  Widget build(BuildContext context) {
    ImageProvider? avatar;

    // 1) Prefer bytes from GET HttpFileData.FileData
    if (customer.imageBytes != null && customer.imageBytes!.isNotEmpty) {
      avatar = MemoryImage(customer.imageBytes!);
    }

    // 2) Base64 string (data URL or stored base64)
    if (avatar == null && (customer.imageB64 ?? '').isNotEmpty) {
      final bytes = _safeDecodeB64(customer.imageB64);
      if (bytes != null && bytes.isNotEmpty) avatar = MemoryImage(bytes);
    }

    // 3) URL from HttpFileData.FileName or Others
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
                backgroundColor: Color(0xFF38B6E4),
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
