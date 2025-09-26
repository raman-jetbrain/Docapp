import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'template_list_page.dart';

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

      if (mounted) {
        setState(() {
          _todayCustomers = matchedCustomers;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _todayCustomers = [];
        });
      }
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
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Day Events',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.white),
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
              'Customers with Birthdays Today 🎉',
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
                        final name = (customer['name'] ?? '') as String;
                        final phone = (customer['phone'] ?? '') as String;

                        return _buildCustomerCard(
                          name: name,
                          phone: phone,
                          photo: customer['photo'],
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TemplateListScreen(customer: {},),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCard({
    required String name,
    required String phone,
    String? photo,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
            CircleAvatar(
              radius: 28,
              backgroundImage: (photo != null && photo.isNotEmpty)
                  ? Image.file(File(photo)).image
                  : const AssetImage("assets/default_avatar.png"),
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
                  Text(
                    phone,
                    style: const TextStyle(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black45),
          ],
        ),
      ),
    );
  }
}