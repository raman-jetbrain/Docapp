import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:docapp/api/customerBus.dart';
import 'package:docapp/descriptionpage.dart';
import 'package:docapp/documentspage.dart';
import 'package:docapp/familydetailspage.dart';
import 'package:docapp/model/customer.dart' as model;
import 'package:docapp/utils/customer_utility.dart'; // <-- use shared resolver/widgets
import 'package:docapp/utils/detailsprofile.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

class CustomerDetailPage extends StatefulWidget {
  final model.Customer customer;
  const CustomerDetailPage({super.key, required this.customer});

  @override
  State<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends State<CustomerDetailPage> {
  final TextEditingController _notesCtrl = TextEditingController();
  String _savedNotes = '';
  String? _photoPath;

  @override
  void initState() {
    super.initState();
    _initAsync();
  }

  Future<void> _initAsync() async {
    await _loadNotes();
    await _persistApiImageIfNeeded(); // Save API image to local file (once)
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  // Provide child pages with an up-to-date customer that includes 'photo' path
  model.Customer get _customerForChildren {
    final map = widget.customer.toMap();
    if (_photoPath != null && _photoPath!.isNotEmpty) {
      map['photo'] = _photoPath;
    }
    return model.Customer.fromMap(map);
  }

  Uint8List? _decodeDataUrl(String? s) {
    if (s == null || s.isEmpty) return null;
    if (!s.startsWith('data:image')) return null;
    try {
      final base64Part = s.split(',').last;
      return base64Decode(base64.normalize(base64Part));
    } catch (_) {
      return null;
    }
  }

  String? _extFromDataUrl(String s) {
    // data:image/png;base64,...
    final i = s.indexOf(';');
    if (!s.startsWith('data:image') || i == -1) return null;
    final mime = s.substring(5, i); // image/png
    final parts = mime.split('/');
    if (parts.length == 2) return parts.last.toLowerCase();
    return null;
  }

  String _guessImageExt(Uint8List bytes) {
    if (bytes.length >= 12) {
      if (bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47) {
        return 'png';
      }
      if (bytes[0] == 0xFF && bytes[1] == 0xD8) return 'jpg';
      if (bytes[0] == 0x47 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x38) {
        return 'gif';
      }
      if (bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50) {
        return 'webp';
      }
    }
    return 'jpg';
  }

  Future<Uint8List?> _downloadImage(String url) async {
    try {
      final uri = Uri.parse(url);
      final client = HttpClient();
      try {
        final req = await client.getUrl(uri);
        final resp = await req.close();
        if (resp.statusCode == 200) {
          final builder = BytesBuilder();
          await for (final chunk in resp) {
            builder.add(chunk);
          }
          return builder.takeBytes();
        }
      } finally {
        client.close(force: true);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _persistApiImageIfNeeded() async {
    // If already have a saved local photo path, do nothing.
    if (_photoPath != null && _photoPath!.isNotEmpty) return;

    Uint8List? bytes;
    String? ext;

    // 1) From Customer.imageBytes
    if (widget.customer.imageBytes != null &&
        widget.customer.imageBytes!.isNotEmpty) {
      bytes = widget.customer.imageBytes!;
      ext = _guessImageExt(bytes);
    } else {
      // 2) From 'others' (data URL or http/https URL)
      final others = widget.customer.others;
      if (others is String && others.isNotEmpty) {
        if (others.startsWith('data:image')) {
          bytes = _decodeDataUrl(others);
          ext = _extFromDataUrl(others) ?? (bytes != null ? _guessImageExt(bytes) : 'jpg');
        } else if (others.startsWith('http://') ||
            others.startsWith('https://')) {
          bytes = await _downloadImage(others);
          if (bytes != null) {
            ext = _guessImageExt(bytes);
          }
        }
      }
    }

    // Nothing to persist
    if (bytes == null || bytes.isEmpty) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final safePhone = widget.customer.phone.replaceAll(RegExp(r'[^0-9A-Za-z]+'), '_');
      final filePath =
          '${dir.path}/cust_${safePhone}_${DateTime.now().millisecondsSinceEpoch}.${ext ?? 'jpg'}';
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);

      // Update prefs and broadcast
      await _upsertLocalPhoto(filePath);

      if (!mounted) return;
      setState(() {
        _photoPath = filePath;
      });
    } catch (_) {
      // best effort
    }
  }

  Future<void> _upsertLocalPhoto(String path) async {
    final prefs = await SharedPreferences.getInstance();

    // 1) Update customers list
    List<dynamic> customersList = [];
    final customersJson = prefs.getString('customers');
    if (customersJson != null && customersJson.isNotEmpty) {
      try {
        customersList = jsonDecode(customersJson);
      } catch (_) {
        customersList = [];
      }
    }
    final idx = customersList.indexWhere(
      (c) => (c is Map) && c['phone'] == widget.customer.phone,
    );
    Map<String, dynamic> updatedMap;
    if (idx >= 0) {
      updatedMap = {
        ...Map<String, dynamic>.from(customersList[idx]),
        'photo': path,
      };
      customersList[idx] = updatedMap;
    } else {
      updatedMap = {
        'name': widget.customer.name,
        'surname': widget.customer.surname,
        'phone': widget.customer.phone,
        'photo': path,
        'notes': _savedNotes,
      };
      customersList.add(updatedMap);
    }
    await prefs.setString('customers', jsonEncode(customersList));

    // 2) Sync last_user if same customer
    final lastUserJson = prefs.getString('last_user');
    if (lastUserJson != null && lastUserJson.isNotEmpty) {
      try {
        final last = jsonDecode(lastUserJson) as Map<String, dynamic>;
        if (last['phone'] == widget.customer.phone) {
          final updatedLast = {...last, 'photo': path};
          await prefs.setString('last_user', jsonEncode(updatedLast));
        }
      } catch (_) {}
    }

    // 3) Broadcast to other pages
    try {
      CustomerBus.notify(model.Customer.fromMap(updatedMap));
    } catch (_) {}
  }

  Future<void> _loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final String? customersJson = prefs.getString('customers');
    if (customersJson != null && customersJson.isNotEmpty) {
      try {
        final List<dynamic> customersList = json.decode(customersJson);
        Map<String, dynamic>? customerData;
        for (final item in customersList) {
          if (item is Map && item['phone'] == widget.customer.phone) {
            customerData = Map<String, dynamic>.from(item);
            break;
          }
        }
        if (customerData != null && mounted) {
          setState(() {
            _savedNotes = (customerData!['notes'] ?? '').toString();
            _photoPath = (customerData['photo'] ?? _photoPath)?.toString();
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final note = _notesCtrl.text.trim();

    List<dynamic> customersList = [];
    final customersJson = prefs.getString('customers');
    if (customersJson != null && customersJson.isNotEmpty) {
      try {
        customersList = jsonDecode(customersJson);
      } catch (_) {
        customersList = [];
      }
    }

    Map<String, dynamic> updatedMap;
    final idx = customersList.indexWhere(
        (c) => (c is Map) && c['phone'] == widget.customer.phone);
    if (idx >= 0) {
      updatedMap = {
        ...Map<String, dynamic>.from(customersList[idx]),
        'notes': note,
        'photo': _photoPath,
      };
      customersList[idx] = updatedMap;
    } else {
      updatedMap = {
        'name': widget.customer.name,
        'surname': widget.customer.surname,
        'phone': widget.customer.phone,
        'notes': note,
        'photo': _photoPath,
      };
      customersList.add(updatedMap);
    }

    await prefs.setString('customers', jsonEncode(customersList));

    // keep last_user in sync if same person
    final lastUserJson = prefs.getString('last_user');
    if (lastUserJson != null && lastUserJson.isNotEmpty) {
      try {
        final last = jsonDecode(lastUserJson) as Map<String, dynamic>;
        if (last['phone'] == widget.customer.phone) {
          final updatedLast = {...last, 'notes': note, 'photo': _photoPath};
          await prefs.setString('last_user', jsonEncode(updatedLast));
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _savedNotes = note);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notes saved!')),
    );

    // broadcast to other pages
    final updatedCustomer = model.Customer.fromMap(updatedMap);
    CustomerBus.notify(updatedCustomer);
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = const Color(0xFF38B6E4);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            backgroundColor: primaryColor,
            leading: Container(
              margin: const EdgeInsets.only(left: 16, top: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 16, top: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.favorite_border, color: Colors.black, size: 24),
                  onPressed: () {},
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CustomerPhoto(
                    customer: _customerForChildren,
                    fit: BoxFit.cover,
                    placeholder: Container(
                      color: primaryColor.withOpacity(0.8),
                      child: Icon(
                        Icons.person,
                        size: 120,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.4),
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withOpacity(0.6),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 20,
                    left: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.customer.name,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: Colors.black,
                                blurRadius: 2.0,
                                offset: Offset(1, 1),
                              ),
                            ],
                          ),
                        ),
                        if (widget.customer.surname.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.customer.surname,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w500,
                              color: Colors.white70,
                              shadows: [
                                Shadow(
                                  color: Colors.black,
                                  blurRadius: 2.0,
                                  offset: Offset(1, 1),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          widget.customer.phone,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withOpacity(0.9),
                            shadows: const [
                              Shadow(
                                color: Colors.black,
                                blurRadius: 2.0,
                                offset: Offset(1, 1),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverList(
            delegate: SliverChildListDelegate(
              [
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(30), topRight: Radius.circular(30)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        _buildSectionCard(
                          title: 'Description',
                          icon: Icons.info_outline,
                          iconColor: primaryColor,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DescriptionPage(customer: _customerForChildren),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildSectionCard(
                          title: 'Documents',
                          icon: Icons.description_outlined,
                          iconColor: primaryColor,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DocumentsPage(customer: _customerForChildren),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildSectionCard(
                          title: 'Family',
                          icon: Icons.family_restroom_outlined,
                          iconColor: primaryColor,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FamilyPage(customer: _customerForChildren),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 32),
                        const Text(
                          'Notes',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _openNotesEditor,
                          child: NotesCard(notes: _savedNotes),
                        ),
                        const SizedBox(height: 20),
                        // Upload/Change Photo button removed as requested
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openNotesEditor() {
    _notesCtrl.text = _savedNotes;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return _NotesEditorCard(
          controller: _notesCtrl,
          onSave: _saveNotes,
        );
      },
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 4,
      shadowColor: Colors.black12,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: iconColor.withOpacity(0.2),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: Colors.black87,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 18, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class NotesCard extends StatelessWidget {
  final String notes;
  const NotesCard({super.key, required this.notes});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      shadowColor: Colors.black12,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 200,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: notes.isEmpty
            ? const Center(
                child: Text(
                  'Tap to add notes',
                  style: TextStyle(fontSize: 16, color: Colors.black45),
                ),
              )
            : SingleChildScrollView(
                child: Text(
                  notes,
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                ),
              ),
      ),
    );
  }
}

class _NotesEditorCard extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSave;
  const _NotesEditorCard({required this.controller, required this.onSave});

  @override
  State<_NotesEditorCard> createState() => _NotesEditorCardState();
}

class _NotesEditorCardState extends State<_NotesEditorCard> {
  late String _initialText;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _initialText = widget.controller.text;
    widget.controller.addListener(_onTextChanged);
    _onTextChanged();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final changed = widget.controller.text != _initialText;
    if (mounted && changed != _changed) {
      setState(() => _changed = changed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      content: Container(
        width: MediaQuery.of(context).size.width * 0.85,
        height: 400,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text('Edit Notes',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: widget.controller,
                maxLines: null,
                expands: true,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Type your notes here...',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel')),
                const Spacer(),
                ElevatedButton(
                  onPressed: _changed ? widget.onSave : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF38B6E4),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Save'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}