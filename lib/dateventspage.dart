import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DayEventsPage extends StatefulWidget {
  const DayEventsPage({super.key});

  @override
  State<DayEventsPage> createState() => _DayEventsPageState();
}

class _DayEventsPageState extends State<DayEventsPage> {
  List<Map<String, dynamic>> _todayCustomers = [];

  @override
  void initState() {
    super.initState();
    _loadTodayCustomers();
  }

  Future<void> _loadTodayCustomers() async {
    final prefs = await SharedPreferences.getInstance();
    final String? customersJson = prefs.getString('customers');

    if (customersJson != null) {
      final List<dynamic> customersList = json.decode(customersJson);

      final now = DateTime.now();
      final todayDay = now.day;
      final todayMonth = now.month;

      List<Map<String, dynamic>> matchedCustomers = [];

      for (var customer in customersList) {
        final dobString = customer['dob'] as String? ?? '';
        if (dobString.isNotEmpty) {
          try {
            final parts = dobString.split('/');
            if (parts.length >= 2) {
              final day = int.parse(parts[0]);
              final month = int.parse(parts[1]);
              if (day == todayDay && month == todayMonth) {
                matchedCustomers.add(Map<String, dynamic>.from(customer));
              }
            }
          } catch (_) {
            // ignore parse errors
          }
        }
      }

      setState(() {
        _todayCustomers = matchedCustomers;
      });
    } else {
      setState(() {
        _todayCustomers = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF38B6E4),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Company Name',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {},
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Day Events of Customers',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            const Divider(thickness: 1),
            const SizedBox(height: 12),
            Expanded(
              child: _todayCustomers.isEmpty
                  ? const Center(
                      child: Text(
                        'No customers with birthdays today.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _todayCustomers.length,
                      itemBuilder: (context, index) {
                        final customer = _todayCustomers[index];
                        return _buildCustomerCard(
                          name: customer['name'] ?? '',
                          phone: customer['phone'] ?? '',
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCard({required String name, required String phone}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 6,
            offset: Offset(2, 2),
          ),
        ],
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          // Circular avatar placeholder
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person,
              size: 30,
              color: Colors.white70,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 1,
                  color: Colors.grey.shade300,
                  margin: const EdgeInsets.only(right: 100),
                ),
                const SizedBox(height: 4),
                Text(
                  phone,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}