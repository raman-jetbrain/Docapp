import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:docapp/model/customermodel.dart' as model;
import 'package:docapp/customerdetailpage.dart';
import 'package:docapp/documentspage.dart';
import 'package:docapp/adduserpage%20.dart';

class FamilyPage extends StatefulWidget {
  final model.Customer customer; // parent

  const FamilyPage({super.key, required this.customer});

  @override
  State<FamilyPage> createState() => _FamilyPageState();
}

class _FamilyPageState extends State<FamilyPage> {
  static const Color kPrimaryBlue = Color(0xFF38B6E4);

  final List<model.Customer> _family = [];
  List<model.Customer> _filtered = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFamily();
    _searchController.addListener(_filter);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filter);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFamily() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('customers');
    if (data == null || data.isEmpty) {
      setState(() {
        _family.clear();
        _filtered = [];
      });
      return;
    }

    try {
      final List<dynamic> customers = json.decode(data);
      final idx = customers.indexWhere((c) => c['phone'] == widget.customer.phone);
      if (idx == -1) {
        setState(() {
          _family.clear();
          _filtered = [];
        });
        return;
      }

      final parent = Map<String, dynamic>.from(customers[idx]);
      final famList = (parent['family'] as List?) ?? [];
      final members = famList
          .map((e) => model.Customer.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();

      setState(() {
        _family
          ..clear()
          ..addAll(members);
        _filter();
      });
    } catch (_) {
      // ignore parse errors
    }
  }

  Future<void> _saveFamily() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('customers');
    final List<dynamic> customers = data != null && data.isNotEmpty ? json.decode(data) : [];

    final idx = customers.indexWhere((c) => c['phone'] == widget.customer.phone);
    final familyMapList = _family.map((m) => m.toMap()).toList();

    if (idx != -1) {
      final parent = Map<String, dynamic>.from(customers[idx]);
      parent['family'] = familyMapList;
      customers[idx] = parent;
    } else {
      customers.add({
        ...widget.customer.toMap(),
        'family': familyMapList,
      });
    }

    await prefs.setString('customers', json.encode(customers));
  }

  void _filter() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filtered = _family.where((m) {
        final nameMatch = m.name.toLowerCase().contains(query);
        final surnameMatch = m.surname.toLowerCase().contains(query);
        final phoneMatch = m.phone.toLowerCase().contains(query);
        return nameMatch || surnameMatch || phoneMatch;
      }).toList();
    });
  }

  Future<void> _addMember() async {
    final newMember = await Navigator.push<model.Customer?>(
      context,
      MaterialPageRoute(builder: (_) => const AddNewUserPage()),
    );

    if (newMember != null) {
      setState(() {
        _family.insert(0, newMember);
        _filter();
      });
      await _saveFamily();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Family member added')),
        );
      }
    }
  }

  Future<void> _removeMember(model.Customer member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Family Member'),
        content: const Text('Are you sure you want to remove this member?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() {
        _family.removeWhere((c) => c.phone == member.phone);
        _filter();
      });
      await _saveFamily();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Removed')),
        );
      }
    }
  }

  void _openDetails(model.Customer member) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CustomerDetailPage(customer: member)),
    );
  }

  void _openDocs(model.Customer member) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DocumentsPage(customer: member)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final padding = width * 0.05;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FC),
      body: CustomScrollView(
        slivers: [
          // SliverAppBar like CustomerScreen
          SliverAppBar(
            expandedHeight: 70,
            pinned: true,
            backgroundColor: Colors.transparent,
            leading: const BackButton(color: Colors.white),
            centerTitle: true,
            title: const Text(
              "Family",
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

          // Main content like CustomerScreen
          SliverFillRemaining(
            child: Column(
              children: [
                // Search bar (same UI)
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
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search, color: Colors.grey),
                        hintText: "Search by name, surname or phone",
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                    ),
                  ),
                ),

                Expanded(
                  child: _filtered.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.family_restroom_outlined, size: 80, color: Colors.grey),
                              SizedBox(height: 10),
                              Text("No family members found",
                                  style: TextStyle(color: Colors.grey, fontSize: 16)),
                            ],
                          ),
                        )
                      : ListView(
                          padding: EdgeInsets.symmetric(horizontal: padding),
                          children: [
                            Text(
                              "Family Members",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: width * 0.045,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ..._filtered.map((member) {
                              return FamilyMemberCard(
                                member: member,
                                onTap: () => _openDetails(member),
                                onDocumentsTap: () => _openDocs(member),
                                onLongPress: () => _removeMember(member), // delete via long-press
                              );
                            }),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),

      // Floating add button
      floatingActionButton: FloatingActionButton(
        backgroundColor: kPrimaryBlue,
        onPressed: _addMember,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

// Same container design as CustomerCard (copied style)
class FamilyMemberCard extends StatelessWidget {
  final model.Customer member;
  final VoidCallback? onTap;
  final VoidCallback? onDocumentsTap;
  final VoidCallback? onLongPress;

  const FamilyMemberCard({
    super.key,
    required this.member,
    this.onTap,
    this.onDocumentsTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress, // long-press to remove (UI unchanged)
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
              backgroundImage: member.imageBytes != null ? MemoryImage(member.imageBytes!) : null,
              child: member.imageBytes == null
                  ? const Icon(Icons.person, size: 30, color: Colors.blueGrey)
                  : null,
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (member.surname.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      member.surname,
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
                    member.phone,
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                    overflow: TextOverflow.ellipsis,
                  ),
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