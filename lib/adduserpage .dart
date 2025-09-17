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
  static const double kScreenPadding = 18;

  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _surnameController = TextEditingController();
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

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _dobController.dispose();
    super.dispose();
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
      labelStyle: const TextStyle(color: Colors.grey, fontSize: 16),
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 14),
      border: InputBorder.none,
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
      "surname": _surnameController.text.trim(),
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

    Navigator.pop(
      context,
      Customer(
        name: newCustomerMap['name'] as String,
        surname: newCustomerMap['surname'] as String,
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        address: _addressController.text.trim(),
        dob: _dobController.text.trim(),
        gender: _gender ?? "",
        customEntries: _customEntries,
        imageBytes: bytes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 60,
            pinned: true,
            backgroundColor: Colors.transparent,
            leading: const BackButton(color: Colors.white),
            title: const Text(
              "Add New Customer",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage("assets/images/Background2.jpeg"),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: kScreenPadding),
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset("assets/images/logo2.png", height: 40, width: 60),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Column(
                  children: [
                    Center(
                      child: GestureDetector(
                        onTap: _pickImage,
                        child: CircleAvatar(
                          radius: 60,
                          backgroundColor: Colors.grey.shade200,
                          backgroundImage: _imageFile != null ? FileImage(_imageFile!) : null,
                          child: _imageFile == null ? const Icon(Icons.person, size: 40, color: Colors.grey) : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    TextField(controller: _nameController, decoration: _inputDecoration("Name")),
                    const Divider(color: Colors.black12),
                    TextField(controller: _surnameController, decoration: _inputDecoration("Surname")),
                    const Divider(color: Colors.black12),
                    TextField(
                      controller: _dobController,
                      readOnly: true,
                      onTap: _pickDate,
                      decoration: _inputDecoration("Date of Birth").copyWith(
                        suffixIcon: const Icon(Icons.keyboard_arrow_down, color: Colors.black54),
                      ),
                    ),
                    const Divider(color: Colors.black12),
                    TextField(controller: _emailController, decoration: _inputDecoration("Email")),
                    const Divider(color: Colors.black12),
                    TextField(controller: _phoneController, decoration: _inputDecoration("Phone No")),
                    const Divider(color: Colors.black12),
                    TextField(controller: _addressController, decoration: _inputDecoration("Address")),
                    const Divider(color: Colors.black12),
                    const SizedBox(height: 20),

                    // Gender selection
                    const Text("Gender", style: TextStyle(color: Colors.grey)),
                    Row(
                      children: ["Male", "Female", "Other"].map((g) {
                        return Expanded(
                          child: Row(
                            children: [
                              Radio<String>(
                                value: g,
                                groupValue: _gender,
                                onChanged: (val) => setState(() => _gender = val),
                                activeColor: Colors.black87,
                              ),
                              Text(g),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                    const Divider(color: Colors.black12),
                    ElevatedButton.icon(
                      onPressed: _showAddCustomEntryDialog,
                      icon: const Icon(Icons.add, color: kPrimaryBlue),
                      label: const Text("Add Custom Entry", style: TextStyle(color: kPrimaryBlue)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        elevation: 0,
                        side: const BorderSide(color: kPrimaryBlue),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_customEntries.isNotEmpty)
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
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
              )
            ]),
          )
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(kScreenPadding),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            image: const DecorationImage(
              image: AssetImage("assets/images/Background2.jpeg"),
              fit: BoxFit.cover,
            ),
          ),
          child: ElevatedButton(
            onPressed: _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text("Submit",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ),
      ),
    );
  }
}