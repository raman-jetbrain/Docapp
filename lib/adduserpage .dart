import 'dart:convert';
import 'dart:io';
import 'package:docapp/model/customermodel.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AddNewUserPage extends StatefulWidget {
  const AddNewUserPage({super.key});

  @override
  State<AddNewUserPage> createState() => _AddNewUserPageState();
}

class _AddNewUserPageState extends State<AddNewUserPage> {
  static const Color kPrimaryBlue = Color(0xFF38B6E4);
  static const double kScreenPadding = 20;
  static const double kRadius = 16;

  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();

  DateTime? _selectedDate;
  String? _gender;
  List<Map<String, String>> _customEntries = [];

  @override
  void initState() {
    super.initState();
    _loadCustomEntries();
  }

  Future<void> _loadCustomEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('custom_entries');
    if (jsonString != null) {
      final List<dynamic> list = json.decode(jsonString);
      setState(() {
        _customEntries = list.map((e) => Map<String, String>.from(e)).toList();
      });
    }
  }

  Future<void> _saveCustomEntries() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_entries', json.encode(_customEntries));
  }

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _imageFile = File(pickedFile.path));
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dobController.text = "${picked.day}/${picked.month}/${picked.year}";
      });
    }
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        color: Colors.black54,
      ),
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadius),
        borderSide: const BorderSide(color: Colors.black26),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: kPrimaryBlue,
      elevation: 0,
      centerTitle: true,
      title: const Text(
        "Add New User",
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12.0),
          child: Image.asset(
            "assets/images/mic-logo.jpeg", // ✅ no leading slash
            height: 35,
            width: 35,
            fit: BoxFit.contain,
          ),
        ),
      ],
    );
  }

  Future<void> _showAddCustomEntryDialog() async {
    final typeController = TextEditingController();
    final detailController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add Custom Entry"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: typeController, decoration: const InputDecoration(labelText: "Type")),
            TextField(controller: detailController, decoration: const InputDecoration(labelText: "Detail")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Add")),
        ],
      ),
    );

    if (result == true) {
      setState(() {
        _customEntries.add({
          "type": typeController.text.trim(),
          "detail": detailController.text.trim(),
        });
      });
      await _saveCustomEntries();
    }
  }

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Name is required")));
      return;
    }

    final bytes = _imageFile != null ? await _imageFile!.readAsBytes() : null;

    final newCustomerMap = {
      "image": bytes != null ? base64Encode(bytes) : "",
      "name": _nameController.text.trim(),
      "phone": _phoneController.text.trim(),
      "address": _addressController.text.trim(),
      "email": _emailController.text.trim(),
      "dob": _dobController.text.trim(),
      "gender": _gender ?? "",
      "customEntries": _customEntries,
    };

    final prefs = await SharedPreferences.getInstance();
    final customersJson = prefs.getString('customers');
    final List<dynamic> list = customersJson != null ? json.decode(customersJson) : [];
    list.add(newCustomerMap);

    await prefs.setString('customers', json.encode(list));
    await prefs.setString('last_user', json.encode(newCustomerMap));

    Navigator.pop(context, Customer(
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      email: _emailController.text.trim(),
      imageBytes: bytes,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      backgroundColor: Colors.grey.shade100,
      body: ListView(
        padding: const EdgeInsets.all(kScreenPadding),
        children: [
          // Profile Image
          Center(
            child: GestureDetector(
              onTap: _pickImage,
              child: CircleAvatar(
                radius: 60,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: _imageFile != null ? FileImage(_imageFile!) : null,
                child: _imageFile == null
                    ? const Icon(Icons.camera_alt, size: 40, color: Colors.black54)
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Personal Info
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(controller: _nameController, decoration: _inputDecoration("Name")),
                  const SizedBox(height: 16),
                  TextField(controller: _phoneController, decoration: _inputDecoration("Phone No"), keyboardType: TextInputType.phone),
                  const SizedBox(height: 16),
                  TextField(controller: _addressController, decoration: _inputDecoration("Address"), maxLines: 2),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _dobController,
                    readOnly: true,
                    onTap: _pickDate,
                    decoration: _inputDecoration("Date of Birth").copyWith(
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Gender Selection
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text("Gender:", style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Wrap(
                      spacing: 20,
                      children: ["Male", "Female", "Other"].map((g) {
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Radio<String>(
                              value: g,
                              groupValue: _gender,
                              onChanged: (val) => setState(() => _gender = val),
                            ),
                            Text(g),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Custom Entries
          ElevatedButton.icon(
            onPressed: _showAddCustomEntryDialog,
            icon: const Icon(Icons.add),
            label: const Text("Add Custom Entry"),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          if (_customEntries.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _customEntries.map((entry) {
                return Chip(
                  label: Text("${entry['type']}: ${entry['detail']}"),
                  backgroundColor: Colors.grey.shade200,
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: () async {
                    setState(() => _customEntries.remove(entry));
                    await _saveCustomEntries();
                  },
                );
              }).toList(),
            ),
        ],
      ),

      // Submit Button
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimaryBlue,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text("Submit", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
