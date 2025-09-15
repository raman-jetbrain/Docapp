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

    final List<Map<String, dynamic>> allCustomersMap = customers.map((c) => c.toMap()).toList();
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
        backgroundColor: const Color(0xFF38B6E4),
        elevation: 0,
        automaticallyImplyLeading: false,
        toolbarHeight: 0,
        flexibleSpace: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.menu, color: Colors.white),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.notifications_none,
                        color: Colors.white,
                      ),
                      onPressed: () {},
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Company Name',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final padding = width * 0.05;
    final searchHeight = 50.0;
    final cardHeight = 100.0;
    final avatarRadius = cardHeight * 0.3;
    final borderColor = Colors.black;

    final isSearching = _searchController.text.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: EdgeInsets.symmetric(horizontal: padding, vertical: 20),
              child: Container(
                height: searchHeight,
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      offset: Offset(1, 1),
                      blurRadius: 2,
                    ),
                  ],
                  border: Border.all(color: borderColor),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(color: Colors.black),
                          decoration: const InputDecoration(
                            hintText: 'Search by name or phone',
                            hintStyle: TextStyle(color: Colors.black54),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 50,
                      height: searchHeight,
                      decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: borderColor)),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.search, color: Colors.black),
                        onPressed: () {
                          FocusScope.of(context).unfocus();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // The rest of the content (conditional based on search)
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: padding),
                child: isSearching
                    ? Column(
                  children: filteredCustomers.map((customer) {
                    return CustomerCard(
                      customer: customer,
                      avatarRadius: avatarRadius,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CustomerDetailPage(customer: customer),
                          ),
                        );
                      },
                      onDocumentsTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DocumentsPage(customer: customer),
                          ),
                        );
                      },
                    );
                  }).toList(),
                )
                    : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Last Enter Customer + Add button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Last Enter Customer',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: width * 0.045,
                            color: borderColor,
                          ),
                        ),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: borderColor),
                            foregroundColor: borderColor,
                          ),
                          onPressed: _navigateToAddUserPage,
                          child: const Text('Add'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    if (lastCustomer != null)
                      CustomerCard(
                        customer: lastCustomer!,
                        avatarRadius: avatarRadius,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CustomerDetailPage(customer: lastCustomer!),
                            ),
                          );
                        },
                        onDocumentsTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DocumentsPage(customer: lastCustomer!),
                            ),
                          );
                        },
                      ),

                    const SizedBox(height: 20),

                    Text(
                      'All Customers',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: width * 0.045,
                        color: borderColor,
                      ),
                    ),
                    const SizedBox(height: 10),

                    ...filteredCustomers.map((customer) {
                      if (lastCustomer != null && customer.phone == lastCustomer!.phone) {
                        return const SizedBox.shrink();
                      }
                      return CustomerCard(
                        customer: customer,
                        avatarRadius: avatarRadius,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CustomerDetailPage(customer: customer),
                            ),
                          );
                        },
                        onDocumentsTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DocumentsPage(customer: customer),
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
    );
  }
}

class CustomerCard extends StatefulWidget {
  final model.Customer customer;
  final double avatarRadius;
  final VoidCallback? onTap;
  final VoidCallback? onDocumentsTap;

  const CustomerCard({
    super.key,
    required this.customer,
    required this.avatarRadius,
    this.onTap,
    this.onDocumentsTap,
  });

  @override
  State<CustomerCard> createState() => _CustomerCardState();
}

class _CustomerCardState extends State<CustomerCard> with SingleTickerProviderStateMixin {
  bool _pressed = false;

  void _onTapDown(TapDownDetails details) {
    setState(() {
      _pressed = true;
    });
  }

  void _onTapUp(TapUpDetails details) {
    setState(() {
      _pressed = false;
    });
  }

  void _onTapCancel() {
    setState(() {
      _pressed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final borderColor = Colors.black;

    return AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 15),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                offset: const Offset(0, 4),
                blurRadius: 8,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                offset: const Offset(0, 2),
                blurRadius: 4,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: widget.avatarRadius,
                backgroundColor: borderColor.withOpacity(0.1),
                backgroundImage: widget.customer.imageBytes != null
                    ? MemoryImage(widget.customer.imageBytes!)
                    : null,
                child: widget.customer.imageBytes == null
                    ? Icon(
                  Icons.person,
                  size: widget.avatarRadius * 1.5,
                  color: Colors.black,
                )
                    : null,
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.customer.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: width * 0.05,
                        color: borderColor,
                      ),
                    ),
                    Divider(color: borderColor),
                    Text(
                      widget.customer.phone,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: width * 0.045,
                        color: borderColor.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: borderColor),
                  foregroundColor: borderColor,
                ),
                onPressed: widget.onDocumentsTap,
                child: const Text('Documents'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}