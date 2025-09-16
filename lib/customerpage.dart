import 'dart:convert';
import 'package:docapp/adduserpage%20.dart';
import 'package:docapp/model/customermodel.dart' as model;
import 'package:flutter/material.dart';
import 'package:docapp/customerdetailpage.dart';
import 'package:docapp/documentspage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CustomerScreen extends StatefulWidget {
  const CustomerScreen({super.key});

  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
  model.Customer? lastCustomer;
  final List<model.Customer> customers = [];
  List<model.Customer> filteredCustomers = [];

  final TextEditingController _searchController = TextEditingController();

  final Color primaryColor = const Color(0xFF38B6E4);

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
      final Map<String, dynamic> userMap = json.decode(userJson);
      setState(() {
        lastCustomer = model.Customer.fromMap(userMap);
      });
    }
  }

  Future<void> _loadCustomers() async {
    customers.clear();

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('customers');

    if (saved != null) {
      final List<dynamic> list = json.decode(saved);
      customers.addAll(
        list.map((e) => model.Customer.fromMap(Map<String, dynamic>.from(e))),
      );
    }

    _filterCustomers();
  }

  void _filterCustomers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      filteredCustomers = customers.where((customer) {
        final nameMatch = customer.name.toLowerCase().contains(query);
        final phoneMatch = customer.phone.toLowerCase().contains(query);
        return nameMatch || phoneMatch;
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
    prefs.setString('last_user', json.encode(newUser.toMap()));

    final List<Map<String, dynamic>> allCustomersMap =
        customers.map((c) => c.toMap()).toList();
    prefs.setString('customers', json.encode(allCustomersMap));
  }

  Future<void> _navigateToAddUserPage() async {
    final newUser = await Navigator.push<model.Customer>(
      context,
      MaterialPageRoute(builder: (context) => const AddNewUserPage()),
    );

    if (newUser != null) {
      _addNewUser(newUser);
    }
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(120.0),
      child: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF38B6E4), Color(0xFF4FD1C5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Column(
          children: [
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  onPressed: () {},
                ),
                const Text(
                  "Company Name",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.notifications_none,
                      color: Colors.white),
                  onPressed: () {},
                ),
              ],
            ),
          ],
        ),
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
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Column(
          children: [
            // Search bar
            Padding(
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
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    hintText: "Search by name or phone",
                    hintStyle: const TextStyle(color: Colors.grey),
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                ),
              ),
            ),

            // Customer list
            Expanded(
              child: filteredCustomers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.people_outline,
                              size: 80, color: Colors.grey),
                          SizedBox(height: 10),
                          Text(
                            "No customers found",
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      padding: EdgeInsets.symmetric(horizontal: padding),
                      children: [
                        if (!isSearching) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Last Entered Customer",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: width * 0.045,
                                ),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: _navigateToAddUserPage,
                                icon: const Icon(Icons.add),
                                label: const Text("Add"),
                              )
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (lastCustomer != null)
                            CustomerCard(
                              customer: lastCustomer!,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        CustomerDetailPage(customer: lastCustomer!),
                                  ),
                                );
                              },
                              onDocumentsTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        DocumentsPage(customer: lastCustomer!),
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
          ],
        ),
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

  @override
  Widget build(BuildContext context) {
    final borderColor = Colors.blueGrey.shade100;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              offset: const Offset(0, 4),
              blurRadius: 6,
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: Colors.blue.shade50,
              backgroundImage: customer.imageBytes != null
                  ? MemoryImage(customer.imageBytes!)
                  : null,
              child: customer.imageBytes == null
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
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    customer.phone,
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38B6E4),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: onDocumentsTap,
              child: const Text("Docs"),
            ),
          ],
        ),
      ),
    );
  }
}
