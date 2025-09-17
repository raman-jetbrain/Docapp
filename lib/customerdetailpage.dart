import 'dart:convert';
import 'package:docapp/documentspage.dart';
import 'package:docapp/model/customermodel.dart' as model;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CustomerDetailPage extends StatefulWidget {
  final model.Customer customer;
  const CustomerDetailPage({super.key, required this.customer});

  @override
  State<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends State<CustomerDetailPage> {
  final TextEditingController _notesCtrl = TextEditingController();
  String _savedNotes = '';

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final String? customersJson = prefs.getString('customers');
    if (customersJson != null && customersJson.isNotEmpty) {
      try {
        final List<dynamic> customersList = json.decode(customersJson);
        final customerData = customersList.firstWhere(
          (c) => c['phone'] == widget.customer.phone,
          orElse: () => null,
        );
        if (customerData != null && mounted) {
          setState(() {
            _savedNotes = (customerData['notes'] ?? '').toString();
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

    final idx = customersList.indexWhere((c) => c['phone'] == widget.customer.phone);
    if (idx >= 0) {
      customersList[idx] = {...customersList[idx], 'notes': note};
    } else {
      customersList.add({
        'name': widget.customer.name,
        'surname': widget.customer.surname,
        'phone': widget.customer.phone,
        'notes': note,
      });
    }

    await prefs.setString('customers', jsonEncode(customersList));

    if (!mounted) return;
    setState(() => _savedNotes = note);
    Navigator.of(context).pop(); // close dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notes saved!')),
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
                  // Customer Image or Placeholder
                  widget.customer.imageBytes != null
                      ? Image.memory(
                          widget.customer.imageBytes!,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: primaryColor.withOpacity(0.8),
                          child: Icon(Icons.person, size: 120, color: Colors.white.withOpacity(0.6)),
                        ),
                  // Gradient Overlay
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
                        stops: const [0.0, 0.5, 0.7, 1.0],
                      ),
                    ),
                  ),
                  // 👉 Customer Name, Surname and Phone Number
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

          // 👉 Body content
          SliverList(
            delegate: SliverChildListDelegate(
              [
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionCard(
                          title: 'Description',
                          icon: Icons.info_outline,
                          iconColor: primaryColor,
                          onTap: () {},
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
                                builder: (_) => DocumentsPage(customer: widget.customer),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildSectionCard(
                          title: 'Family',
                          icon: Icons.family_restroom_outlined,
                          iconColor: primaryColor,
                          onTap: () {},
                        ),
                        const SizedBox(height: 32),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8.0),
                          child: Text(
                            'Notes',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _openNotesEditor,
                          child: NotesCard(notes: _savedNotes),
                        ),
                        const SizedBox(height: 20),
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

extension on model.Customer {
  Null get surname => null;
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
        height: 250,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: notes.isEmpty
            ? const Center(
                child: Text(
                  'Tap to add notes',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.black45,
                  ),
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

  const _NotesEditorCard({
    required this.controller,
    required this.onSave,
  });

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
      contentPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      content: Container(
        width: MediaQuery.of(context).size.width * 0.85,
        height: 450,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              'Edit Notes',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 22, color: Colors.black87),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: widget.controller,
                maxLines: null,
                expands: true,
                autofocus: true,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  hintText: 'Type your notes here...',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                ),
                style: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                const Spacer(),
                if (widget.controller.text.isNotEmpty)
                  TextButton(onPressed: () => widget.controller.clear(), child: const Text('Clear')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _changed ? widget.onSave : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF38B6E4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text('Save', style: TextStyle(fontSize: 16, color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}