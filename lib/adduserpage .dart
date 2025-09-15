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
  static const double kFieldHeight = 54;

  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

  // Controllers for fields
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  // Date of Birth
  DateTime? _selectedDate;
  final TextEditingController _dobController = TextEditingController();

  // Gender
  String? _gender;

  // Custom entries
  List<Map<String, String>> _customEntries = [];

  @override
  void initState() {
    super.initState();
    _loadCustomEntries();
  }

  Future<void> _loadCustomEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString('custom_entries');
    if (jsonString != null) {
      final List<dynamic> jsonList = json.decode(jsonString);
      setState(() {
        _customEntries = jsonList.map((e) => Map<String, String>.from(e)).toList();
      });
    }
  }

  Future<void> _saveCustomEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonString = json.encode(_customEntries);
    await prefs.setString('custom_entries', jsonString);
  }

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint.toUpperCase(),
      hintStyle: const TextStyle(
        color: Color(0xFF6F6F6F),
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadius),
        borderSide: const BorderSide(color: Color(0xFF3F3F3F), width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadius),
        borderSide: const BorderSide(color: Color(0xFF3F3F3F), width: 1.4),
      ),
    );
  }

  BoxDecoration get _fieldDecorationShadow => BoxDecoration(
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            spreadRadius: 0,
            offset: Offset(0, 4),
          ),
        ],
        borderRadius: BorderRadius.circular(kRadius),
      );

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(120.0),
      child: AppBar(
        backgroundColor: kPrimaryBlue,
        elevation: 0,
        automaticallyImplyLeading: false,
        flexibleSpace: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Top row (menu and notifications)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.menu, color: Colors.white),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.notifications_none, color: Colors.white),
                      onPressed: () {},
                    ),
                  ],
                ),
                // Title row with back icon and centered title
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
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

  Future<void> _showAddCustomEntryDialog() async {
    final typeController = TextEditingController();
    final detailController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add New Entry'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: typeController,
                decoration: const InputDecoration(labelText: 'Type'),
              ),
              TextField(
                controller: detailController,
                decoration: const InputDecoration(labelText: 'Detail'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (typeController.text.trim().isEmpty || detailController.text.trim().isEmpty) {
                  return;
                }
                Navigator.of(context).pop(true);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      setState(() {
        _customEntries.add({
          'type': typeController.text.trim(),
          'detail': detailController.text.trim(),
        });
      });
      await _saveCustomEntries();
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime(2000, 1, 1),
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

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required')),
      );
      return;
    }

    // Prepare image bytes for return and storage
    final bytes = _imageFile != null ? await _imageFile!.readAsBytes() : null;

    // Build the Customer to return to CustomerScreen
    final customerToReturn = Customer(
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      email: _emailController.text.trim(),
      imageBytes: bytes,
    );

    // Persist in SharedPreferences (keeps extra fields too)
    final prefs = await SharedPreferences.getInstance();
    final String? customersJson = prefs.getString('customers');
    final List<dynamic> customersList = customersJson != null ? json.decode(customersJson) : [];

    final newCustomerMap = {
      'image': bytes != null ? base64Encode(bytes) : '',
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'address': _addressController.text.trim(),
      'email': _emailController.text.trim(),
      'dob': _dobController.text.trim(),
      'gender': _gender ?? '',
      'customEntries': _customEntries,
    };

    customersList.add(newCustomerMap);
    await prefs.setString('customers', json.encode(customersList));
    await prefs.setString('last_user', json.encode(newCustomerMap));

    // Return the new customer back to the previous screen
    Navigator.of(context).pop(customerToReturn);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Submit',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Title centered (below appbar)
            const Padding(
              padding: EdgeInsets.fromLTRB(kScreenPadding, 14, kScreenPadding, 10),
              child: Center(
                child: Text(
                  'Add New User',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: kScreenPadding),
              child: Divider(
                thickness: 1,
                color: Color(0xFFBDBDBD),
              ),
            ),

            // Top row: Upload Image + (Name, Phone)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kScreenPadding, vertical: 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Upload image box
                  InkWell(
                    onTap: _pickImage,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 122,
                      height: 122,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF3F3F3F), width: 1.4),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          )
                        ],
                      ),
                      child: _imageFile == null
                          ? const Center(
                              child: Text(
                                'UPLOAD\nIMAGE',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                  height: 1.15,
                                ),
                              ),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                _imageFile!,
                                fit: BoxFit.cover,
                                width: 122,
                                height: 122,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(width: 18),

                  // Name + Phone fields stacked vertically
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          decoration: _fieldDecorationShadow,
                          child: SizedBox(
                            height: kFieldHeight,
                            child: TextField(
                              controller: _nameController,
                              decoration: _inputDecoration('Name'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          decoration: _fieldDecorationShadow,
                          child: SizedBox(
                            height: kFieldHeight,
                            child: TextField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: _inputDecoration('Phone No'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 5),

            // Center aligned fields below the row
            Center(
              child: SizedBox(
                width: 400,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Address
                    Container(
                      decoration: _fieldDecorationShadow,
                      child: SizedBox(
                        height: kFieldHeight,
                        child: TextField(
                          controller: _addressController,
                          maxLines: 2,
                          decoration: _inputDecoration('Address'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Date of Birth (with date picker)
                    TextField(
                      controller: _dobController,
                      readOnly: true,
                      decoration: _inputDecoration('Date of Birth').copyWith(
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.calendar_today),
                          onPressed: _pickDate,
                        ),
                      ),
                      onTap: _pickDate,
                    ),
                    const SizedBox(height: 16),

                    // Gender selection (radio buttons)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF3F3F3F), width: 1.2),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          )
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Gender:',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: Color(0xFF6F6F6F),
                            ),
                          ),
                          const SizedBox(width: 20),
                          Row(
                            children: [
                              Radio<String>(
                                value: 'Male',
                                groupValue: _gender,
                                onChanged: (val) => setState(() => _gender = val),
                              ),
                              const Text('Male'),
                              Radio<String>(
                                value: 'Female',
                                groupValue: _gender,
                                onChanged: (val) => setState(() => _gender = val),
                              ),
                              const Text('Female'),
                              Radio<String>(
                                value: 'Other',
                                groupValue: _gender,
                                onChanged: (val) => setState(() => _gender = val),
                              ),
                              const Text('Other'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Add Custom Entry button
                    GestureDetector(
                      onTap: _showAddCustomEntryDialog,
                      child: Container(
                        height: kFieldHeight,
                        decoration: _fieldDecorationShadow.copyWith(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(kRadius),
                          border: Border.all(color: const Color(0xFF3F3F3F), width: 1.2),
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: const Text(
                          'Add Custom Entry',
                          style: TextStyle(
                            color: Color(0xFF6F6F6F),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Show list of saved custom entries
            if (_customEntries.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: kScreenPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Custom Entries:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._customEntries.map((entry) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '${entry['type']}: ${entry['detail']}',
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 20, color: Colors.redAccent),
                              onPressed: () async {
                                setState(() {
                                  _customEntries.remove(entry);
                                });
                                await _saveCustomEntries();
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),

            const SizedBox(height: 260),
          ],
        ),
      ),
    );
  }
}