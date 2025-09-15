import 'dart:convert';
import 'package:docapp/adduserpage%20.dart';
import 'package:docapp/customerpage.dart';
import 'package:docapp/dateventspage.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Dashboard',
      theme: ThemeData(
        fontFamily: 'Montserrat', // You might need to add this font to your project
        primaryColor: const Color(0xFF3B5998),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B5998)),
      ),
      home: const Dashboardpage(),
    );
  }
}

// Colors from the design
const kPrimaryBlue = Color(0xFF3B5998);
const kShadowColor = Color(0xFFE5E5E5);

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
          } catch (_) {
            // ignore parse errors
          }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                _buildHeader(),
                const SizedBox(height: 30),
                _buildSearchBar(),
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
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hello,',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w400,
                color: Color(0xFF6B7280),
              ),
            ),
            Text(
              'Company Name',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.black.withOpacity(0.85),
              ),
            ),
          ],
        ),
        const CircleAvatar(
          radius: 25,
          backgroundColor: Colors.grey, // Placeholder for an image
          child: Icon(Icons.person, color: Colors.white),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.search, color: Color(0xFF9CA3AF)),
          SizedBox(width: 8),
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search for customers',
                hintStyle: TextStyle(color: Color(0xFF9CA3AF)),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Today\'s Events',
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
                'Today\'s Birthday',
                '$_birthdayCount',
                Icons.cake,
                const Color(0xFFFCE1C2),
                () => _navigateTodayEventsPage(),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _buildEventCard(
                'Total Customers',
                '$_customerCount',
                Icons.groups,
                const Color(0xFFC2D9FC),
                () => _navigateToCustomerScreen(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEventCard(
      String title, String count, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 150, // Set a fixed height
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
            Icon(
              icon,
              size: 40,
              color: kPrimaryBlue,
            ),
            const SizedBox(height: 8),
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
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
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
          _buildNavBarItem(Icons.person, 'Profile', false),
        ],
      ),
    );
  }

  Widget _buildNavBarItem(IconData icon, String label, bool isSelected) {
    return InkWell(
      onTap: () {
        // Implement navigation logic here
        if (label == 'Customers') {
          _navigateToCustomerScreen();
        } else if (label == 'Add') {
          _navigateToAddUserPage();
        } else if (label == 'Events') {
          _navigateTodayEventsPage();
        }
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: isSelected ? kPrimaryBlue : Colors.grey[400],
            size: 28,
          ),
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
}