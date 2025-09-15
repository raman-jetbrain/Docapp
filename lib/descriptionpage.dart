import 'dart:typed_data';
import 'package:docapp/model/description.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

// Customer model
class Customer {
  final String name;
  final String phone;
  final Uint8List? imageBytes;

  Customer({
    required this.name,
    required this.phone,
    this.imageBytes,
  });

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      name: map['name'],
      phone: map['phone'],
      imageBytes: map['imageBytes'] != null
          ? Uint8List.fromList(List<int>.from(map['imageBytes']))
          : null,
    );
  }
}


class DescriptionPage extends StatefulWidget {
  const DescriptionPage({super.key});

  @override
  State<DescriptionPage> createState() => _DescriptionPageState();
}

class _DescriptionPageState extends State<DescriptionPage> {
  late Database _db;
  Customer? _customer;
  List<DescriptionEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initDbAndLoad();
  }

  Future<void> _initDbAndLoad() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'app.db');

    _db = await openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE customers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT,
          phone TEXT,
          imageBytes BLOB
        )
      ''');

      await db.execute('''
        CREATE TABLE descriptions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customerName TEXT,
          title TEXT,
          category TEXT,
          amount REAL,
          icon TEXT
        )
      ''');

      // Insert demo customer
      await db.insert('customers', {
        'name': 'Demo User',
        'phone': '123-456-7890',
        'imageBytes': null,
      });

      // Insert demo descriptions for Demo User
      await db.insert('descriptions', {
        'customerName': 'Demo User',
        'title': 'Adidas',
        'category': 'Shopping',
        'amount': -45.00,
        'icon': '👕',
      });
      await db.insert('descriptions', {
        'customerName': 'Demo User',
        'title': 'Birthday',
        'category': 'Revenue',
        'amount': 100.00,
        'icon': '🎂',
      });
      await db.insert('descriptions', {
        'customerName': 'Demo User',
        'title': 'Netflix',
        'category': 'Entertainment',
        'amount': -7.99,
        'icon': '📺',
      });
      await db.insert('descriptions', {
        'customerName': 'Demo User',
        'title': 'Spotify',
        'category': 'Entertainment',
        'amount': -4.99,
        'icon': '🎧',
      });
      await db.insert('descriptions', {
        'customerName': 'Demo User',
        'title': 'Starbucks',
        'category': 'Food',
        'amount': -5.45,
        'icon': '☕',
      });
    });

    await _loadCustomerAndEntries();
  }

  Future<void> _loadCustomerAndEntries() async {
    // Load first customer (for demo)
    final List<Map<String, dynamic>> customerMaps = await _db.query('customers', limit: 1);

    if (customerMaps.isEmpty) {
      setState(() {
        _loading = false;
      });
      return;
    }

    final customer = Customer.fromMap(customerMaps.first);

    // Load descriptions for this customer
    final List<Map<String, dynamic>> descriptionMaps = await _db.query(
      'descriptions',
      where: 'customerName = ?',
      whereArgs: [customer.name],
    );

    setState(() {
      _customer = customer;
      _entries = descriptionMaps.map((e) => DescriptionEntry.fromMap(e)).toList();
      _loading = false;
    });
  }

  @override
  void dispose() {
    _db.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(30);
    final bgColor = Colors.yellow.shade100;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _customer == null
                ? const Center(child: Text('No customer data found'))
                : Column(
                    children: [
                      // Profile top section
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: borderRadius,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 12,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 50,
                              backgroundColor: Colors.grey.shade300,
                              backgroundImage: _customer!.imageBytes != null
                                  ? MemoryImage(_customer!.imageBytes!)
                                  : null,
                              child: _customer!.imageBytes == null
                                  ? const Icon(Icons.person, size: 50, color: Colors.grey)
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _customer!.name,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _customer!.phone,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),

                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: _entries.length,
                          itemBuilder: (context, index) {
                            final entry = _entries[index];
                            final isPositive = entry.amount >= 0;
                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 8,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: Colors.grey.shade200,
                                    child: Text(
                                      entry.icon,
                                      style: const TextStyle(fontSize: 24),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          entry.category,
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${isPositive ? '+' : '-'}${entry.amount.abs().toStringAsFixed(2)}€',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: isPositive ? Colors.green : Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),

                      // Social icons row
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.camera_alt, size: 28),
                            SizedBox(width: 24),
                            Icon(Icons.alternate_email, size: 28),
                            SizedBox(width: 24),
                            Icon(Icons.video_library, size: 28),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}