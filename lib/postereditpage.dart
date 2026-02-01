import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:docapp/api/customer_api_service.dart';
import 'package:docapp/model/customer.dart' as model;
import 'package:docapp/utils/wish_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PosterSharePage extends StatefulWidget {
  final model.Customer customer;

  /// Caption text to share along with the poster (passed from Birthday/Anniversary page).
  final String? shareMessage;

  const PosterSharePage({
    super.key,
    required this.customer,
    this.shareMessage,
  });

  @override
  State<PosterSharePage> createState() => _PosterSharePageState();
}

class _PosterSharePageState extends State<PosterSharePage> {
  final ImagePicker picker = ImagePicker();

  // API service
  final CustomerApiService _api = CustomerApiService();

  // Working copy (will be hydrated from API)
  late model.Customer _customer;

  // Loading state for fetching full details
  bool _loadingCustomer = false;
  String? _loadError;

  // Templates (persisted)
  final List<File> _templates = [];
  int? _selectedIndex;

  // Canvas capture key
  final GlobalKey _canvasKey = GlobalKey();

  // Template storage
  final _store = _PosterTemplateStore();

  // Name color state
  Color _nameColor = const Color(0xFF5D4037);

  // Keys for DOB/Anniversary (same as Dashboard)
  static const List<String> _dobKeys = [
    'dob', 'DOB', 'dateOfBirth', 'birthdate', 'birthDate', 'date_of_birth', 'birthday'
  ];
  static const List<String> _annivKeys = [
    'anniversary', 'anniversaryDate', 'wedding_anniversary', 'doa', 'dom',
    'dateOfAnniversary', 'marriageDate', 'MarriedDate'
  ];

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    _loadTemplates();
    _hydrateCustomerFromApi();
  }

  Future<void> _hydrateCustomerFromApi() async {
    setState(() {
      _loadingCustomer = true;
      _loadError = null;
    });

    try {
      // Prefer server id
      final baseMap = _customer.toMap();
      final id = (baseMap['serverId'] ?? baseMap['id'] ?? '').toString().trim();

      model.Customer? fetched;
      if (id.isNotEmpty && id.toLowerCase() != 'null') {
        fetched = await _api.getCustomerById(id);
      }

      // Fallback by phone if no id or not found
      fetched ??= await _api.getCustomerByPhone(_customer.phone);

      // If still not found, fallback to latest from list
      if (fetched == null) {
        try {
          final list = await _api.getCustomers();
          fetched = list.firstWhere(
            (c) => c.phone.trim() == _customer.phone.trim(),
            orElse: () => _customer,
          );
        } catch (_) {}
      }

      if (fetched != null) {
        var updated = fetched;

        // If image missing but we have a positive fileId, hydrate bytes
        final hasBytes = updated.imageBytes != null && updated.imageBytes!.isNotEmpty;
        final hasUrl = (updated.others ?? '').startsWith('http');
        final fid = updated.fileId is int
            ? updated.fileId as int
            : int.tryParse(updated.fileId?.toString() ?? '');

        if (!hasBytes && !hasUrl && fid != null && fid > 0) {
          try {
            final bytes = await _api.fetchFileBytesById(fid);
            if (bytes != null && bytes.isNotEmpty) {
              final m = updated.toMap();
              m['imageBytes'] = bytes;
              m['imageB64'] = null;
              updated = model.Customer.fromMap(m);
            }
          } catch (e) {
            debugPrint('[Poster] fetchFileBytesById($fid) failed: $e');
          }
        }

        if (mounted) {
          setState(() => _customer = updated);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingCustomer = false);
    }
  }

  Future<void> _loadTemplates() async {
    await _store.ensureDefaultsLoaded();
    final list = await _store.listTemplates();
    setState(() {
      _templates
        ..clear()
        ..addAll(list);

      if (_templates.isEmpty) {
        _selectedIndex = null;
        return;
      }

      // Prefer a default template matching today's event type for this customer
      final type = _todayEventTypeForCustomer();
      if (type != null) {
        final tag = type == 'birthday' ? 'bday' : 'anniv';
        final idx = _templates.indexWhere(
          (f) => p.basename(f.path).toLowerCase().contains(tag),
        );
        _selectedIndex = idx != -1 ? idx : 0;
      } else {
        _selectedIndex = 0;
      }
    });
  }

  // Pick images and save as templates (persist)
  Future<void> _pickTemplates() async {
    try {
      final files = await picker.pickMultiImage(imageQuality: 90);
      if (files.isEmpty) return;

      for (final xf in files) {
        await _store.addTemplate(File(xf.path));
      }
      await _loadTemplates();
      setState(() {
        _selectedIndex = _templates.isNotEmpty ? 0 : null;
      });
    } catch (e) {
      debugPrint('pick templates error: $e');
    }
  }

  // Delete a template
  Future<void> _deleteTemplateAt(int index) async {
    if (index < 0 || index >= _templates.length) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete template'),
        content: const Text('Remove this template permanently?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _store.deleteTemplate(_templates[index]);
      await _loadTemplates();
    } catch (e) {
      debugPrint('delete template error: $e');
    }
  }

  // Current selected file
  File? get _selectedFile {
    final i = _selectedIndex;
    if (i == null || i < 0 || i >= _templates.length) return null;
    return _templates[i];
  }

  // Build avatar provider from customer model
  ImageProvider? _customerAvatarProvider(model.Customer c) {
    if (c.imageBytes != null && c.imageBytes!.isNotEmpty) {
      return MemoryImage(c.imageBytes!);
    }
    final b64 = (c.imageB64 ?? '').trim();
    if (b64.isNotEmpty) {
      try {
        var s = b64;
        final comma = s.indexOf(',');
        if (comma != -1 && s.substring(0, comma).toLowerCase().contains('base64')) {
          s = s.substring(comma + 1);
        }
        final bytes = base64Decode(base64.normalize(s.replaceAll(RegExp(r'\s'), '')));
        if (bytes.isNotEmpty) return MemoryImage(bytes);
      } catch (_) {}
    }
    final others = c.others?.trim() ?? '';
    if (others.startsWith('http://') || others.startsWith('https://')) {
      return NetworkImage(others);
    }
    return null;
  }

  // Show only the name (no surname)
  String _customerDisplayName(model.Customer c) {
    final n = c.name.trim();
    return n.isNotEmpty ? n : 'Customer';
  }

  // Export and save to app documents (poster_exports)
  Future<void> _exportPoster() async {
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a template first.')),
      );
      return;
    }
    try {
      await Future.delayed(const Duration(milliseconds: 50));
      final boundary = _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Render boundary not found');

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to encode PNG');

      final pngBytes = byteData.buffer.asUint8List();
      final out = await _store.saveExport(pngBytes);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Poster saved: ${out.path}')),
      );
    } catch (e) {
      debugPrint('export error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  // Render the poster to a temporary PNG (used for Share)
  Future<File?> _renderPosterToFile() async {
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a template first.')),
      );
      return null;
    }
    try {
      await Future.delayed(const Duration(milliseconds: 50));
      final boundary = _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Render boundary not found');

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to encode PNG');

      final pngBytes = byteData.buffer.asUint8List();
      final tmp = await getTemporaryDirectory();
      final out = File(p.join(tmp.path, 'poster_${DateTime.now().millisecondsSinceEpoch}.png'));
      await out.writeAsBytes(pngBytes, flush: true);
      return out;
    } catch (e) {
      debugPrint('render error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Render failed: $e')),
      );
      return null;
    }
  }

  // Caption used for WhatsApp / any share target
  String _buildShareCaption() {
    return widget.shareMessage ??
        "On your special day, Maruthi Insure Care wishes you happiness, "
        "good health, and continued success. Your support means a lot to us";
  }

  // Detect today's event type for this customer
  String? _todayEventTypeForCustomer() {
    final dob = _firstDateByKeys(_customer.toMap(), _dobKeys);
    final isBday = _isTodayMonthDay(dob);

    final anniv = _firstDateByKeys(_customer.toMap(), _annivKeys);
    final isAnniv = _isTodayMonthDay(anniv);

    if (isBday && !isAnniv) return 'birthday';
    if (isAnniv && !isBday) return 'anniversary';
    if (isBday && isAnniv) return 'birthday';
    return null;
  }

  Future<void> _markWishDoneForToday() async {
    final type = _todayEventTypeForCustomer();
    final phone = (_customer.phone ?? '').toString().trim();
    if (type == null || phone.isEmpty) return;
    await WishTracker.markDone(phone: phone, type: type);
  }

  // Share via Share Plus with caption (user selects WhatsApp)
  Future<void> _sharePoster() async {
    final file = await _renderPosterToFile();
    if (file == null) return;

    final caption = _buildShareCaption();

    try {
      // This opens the system share sheet. When the user selects WhatsApp,
      // WhatsApp will receive this image + caption text.
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: caption,
        subject: 'Warm wishes from Maruthi Insure Care',
      );

      await _markWishDoneForToday();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shared. Marked as done for today.')),
      );
    } catch (e) {
      debugPrint('share error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not share: $e')),
      );
    }
  }

  void _openNameColorPicker() {
    final colors = <Color>[
      Colors.white,
      Colors.black,
      const Color(0xFF5D4037),
      Colors.red,
      Colors.pink,
      Colors.purple,
      Colors.indigo,
      Colors.blue,
      Colors.teal,
      Colors.green,
      Colors.lime,
      Colors.orange,
      Colors.amber,
      Colors.brown,
      Colors.grey,
    ];

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Pick name color', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in colors)
                    GestureDetector(
                      onTap: () {
                        setState(() => _nameColor = c);
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: c.computeLuminance() > 0.5 ? Colors.black26 : Colors.white24,
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: _nameColor == c
                            ? const Icon(Icons.check, size: 18, color: Colors.white)
                            : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final customer = _customer;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        toolbarHeight: 60,
        backgroundColor: Colors.transparent,
        centerTitle: true,
        leading: const BackButton(color: Colors.white),
        title: const Text(
          '',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_loadingCustomer)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Refresh details',
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _hydrateCustomerFromApi,
          ),
          IconButton(
            tooltip: 'Name color',
            icon: const Icon(Icons.color_lens_outlined, color: Colors.white),
            onPressed: _openNameColorPicker,
          ),
          IconButton(
            tooltip: 'Add template',
            icon: const Icon(Icons.add_photo_alternate_outlined, color: Colors.white),
            onPressed: _pickTemplates,
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share_outlined, color: Colors.white),
            onPressed: _sharePoster,
          ),
        ],
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage("assets/images/Background2.jpeg"),
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _selectedFile != null
          ? FloatingActionButton.extended(
              onPressed: _sharePoster,
              icon: const Icon(Icons.send),
              label: const Text('Send'),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            if (_loadError != null)
              Container(
                width: double.infinity,
                color: Colors.red.withOpacity(0.06),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _loadError!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(onPressed: _hydrateCustomerFromApi, child: const Text('Retry')),
                  ],
                ),
              ),

            // Preview canvas
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _selectedFile != null
                      ? Stack(
                          children: [
                            RepaintBoundary(
                              key: _canvasKey,
                              child: _PosterCanvas(
                                templateFile: _selectedFile!,
                                customer: customer,
                                avatarProvider: _customerAvatarProvider(customer),
                                customerDisplayName: _customerDisplayName(customer),
                                nameColor: _nameColor,
                              ),
                            ),
                            if (_loadingCustomer)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Container(
                                    color: Colors.black.withOpacity(0.08),
                                  ),
                                ),
                              ),
                          ],
                        )
                      : _buildAddPrompt(),
                ),
              ),
            ),

            // Bottom thumbnails bar
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Colors.grey, width: 0.3),
                ),
              ),
              child: SizedBox(
                height: 90,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _addTile(),
                    ...List.generate(
                      _templates.length,
                      (i) => _thumb(i),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Default "Add" prompt in the large preview area
  Widget _buildAddPrompt() {
    return InkWell(
      onTap: _pickTemplates,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_photo_alternate_outlined, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 8),
            Text(
              'Add poster templates',
              style: TextStyle(fontSize: 16, color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }

  // The first tile in the bottom bar: add item
  Widget _addTile() {
    return GestureDetector(
      onTap: _pickTemplates,
      child: Container(
        width: 60,
        height: 60,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blueAccent),
        ),
        child: const Icon(Icons.add, color: Colors.blueAccent),
      ),
    );
  }

  // Thumbnail for each item
  Widget _thumb(int index) {
    final isSelected = index == _selectedIndex;

    return GestureDetector(
      onTap: () {
        setState(() => _selectedIndex = index);
      },
      onLongPress: () => _deleteTemplateAt(index),
      child: Container(
        width: 60,
        height: 60,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.blueAccent : Colors.transparent,
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            _templates[index],
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  // === Count helpers kept for compatibility (not needed for caption) ===

  Future<_Counts> _loadTodayCounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customersJson = prefs.getString('customers');
      if (customersJson == null || customersJson.trim().isEmpty) {
        return const _Counts(0, 0);
      }
      final customers = _decodeCustomers(customersJson);

      int birthdayCount = 0;
      int anniversaryCount = 0;

      for (final m in customers) {
        final dob = _firstDateByKeys(m, _dobKeys);
        if (_isTodayMonthDay(dob)) birthdayCount++;

        final anniv = _firstDateByKeys(m, _annivKeys);
        if (_isTodayMonthDay(anniv)) anniversaryCount++;
      }
      return _Counts(birthdayCount, anniversaryCount);
    } catch (e) {
      debugPrint('count load error: $e');
      return const _Counts(0, 0);
    }
  }

  List<Map<String, dynamic>> _decodeCustomers(String jsonStr) {
    final List<Map<String, dynamic>> out = [];
    dynamic decoded;
    try {
      decoded = json.decode(jsonStr);
    } catch (e) {
      debugPrint('[Poster] JSON decode error: $e');
      return out;
    }

    void addList(dynamic v) {
      if (v is List) {
        for (final e in v) {
          if (e is Map) out.add(Map<String, dynamic>.from(e));
        }
      }
    }

    if (decoded is List) {
      addList(decoded);
    } else if (decoded is Map) {
      final m = Map<String, dynamic>.from(decoded);
      final candidates = ['customers', 'data', 'items', 'list', 'result'];
      bool added = false;
      for (final k in candidates) {
        if (m[k] is List) {
          addList(m[k]);
          added = true;
          break;
        }
      }
      if (!added) {
        out.add(m);
      }
    }
    return out;
  }

  String? _toDateString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v.trim();
    if (v is int) return v.toString();
    if (v is double) return v.toInt().toString();
    if (v is Map) {
      final ms = v['milliseconds'] ?? v['millis'] ?? v['ms'];
      if (ms != null) return ms.toString();
      final sec = v['seconds'] ?? v['secs'] ?? v['s'];
      if (sec != null) {
        final s = int.tryParse(sec.toString());
        if (s != null) return (s * 1000).toString();
      }
    }
    return v.toString();
  }

  String? _firstDateByKeys(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k) && m[k] != null) {
        return _toDateString(m[k]);
      }
    }
    return null;
  }

  bool _isTodayMonthDay(String? raw) {
    final dt = _parseDateFlex(raw);
    if (dt == null) return false;
    final now = DateTime.now();
    return dt.day == now.day && dt.month == now.month;
  }

  DateTime? _parseDateFlex(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;

    // Pure digits => epoch (ms or sec)
    if (RegExp(r'^\d+$').hasMatch(s)) {
      final n = int.tryParse(s);
      if (n != null) {
        if (s.length >= 12) return DateTime.fromMillisecondsSinceEpoch(n);
        if (s.length == 10) return DateTime.fromMillisecondsSinceEpoch(n * 1000);
      }
    }

    // ISO or yyyy-MM-dd
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso.isUtc ? iso.toLocal() : iso;

    // Normalize separators and try dd/MM, dd-MM-yyyy, etc.
    final norm = s.replaceAll('/', '-').replaceAll('.', '-');
    final parts = norm.split('-').where((e) => e.trim().isNotEmpty).toList();

    if (parts.length >= 3) {
      if (parts[0].length == 4) {
        final y = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        final d = int.tryParse(parts[2]) ?? 0;
        if (y > 0 && m > 0 && d > 0) return DateTime(y, m, d);
      } else {
        final d = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        int y = int.tryParse(parts[2]) ?? 0;
        if (y > 0 && y < 100) y += 2000;
        if (y > 0 && m > 0 && d > 0) return DateTime(y, m, d);
      }
    }

    if (parts.length >= 2) {
      // dd-MM (no year)
      final now = DateTime.now();
      final d = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      if (m > 0 && d > 0) return DateTime(now.year, m, d);
    }

    // Fallback: extract numbers in order
    final nums = RegExp(r'\d+').allMatches(s).map((m) => m.group(0)!).toList();
    if (nums.length >= 3 && nums[0].length == 4) {
      final y = int.tryParse(nums[0]) ?? 0;
      final mm = int.tryParse(nums[1]) ?? 0;
      final d = int.tryParse(nums[2]) ?? 0;
      if (y > 0 && mm > 0 && d > 0) return DateTime(y, mm, d);
    } else if (nums.length >= 2) {
      final now = DateTime.now();
      final d = int.tryParse(nums[0]) ?? 0;
      final mm = int.tryParse(nums[1]) ?? 0;
      if (mm > 0 && d > 0) return DateTime(now.year, mm, d);
    }

    return null;
  }
}

class _Counts {
  final int birthdays;
  final int anniversaries;
  const _Counts(this.birthdays, this.anniversaries);
}

// Canvas: shows the selected template with the customer block on bottom-left
class _PosterCanvas extends StatelessWidget {
  final File templateFile;
  final model.Customer customer;
  final ImageProvider? avatarProvider;
  final String customerDisplayName;
  final Color nameColor;

  const _PosterCanvas({
    required this.templateFile,
    required this.customer,
    required this.avatarProvider,
    required this.customerDisplayName,
    required this.nameColor,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final dim = math.min(w, h);

        // Bigger avatar radius
        final avatarRadius = math.max(32.0, dim * 0.10);

        return Stack(
          fit: StackFit.expand,
          children: [
            // Template image as background
            Image.file(
              templateFile,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
            // Customer badge at bottom-left
            Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                margin: const EdgeInsets.all(16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Avatar with a shadow
                    Material(
                      elevation: 6.0,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: CircleAvatar(
                        radius: avatarRadius,
                        backgroundColor: Colors.blue.shade50,
                        backgroundImage: avatarProvider,
                        child: avatarProvider == null
                            ? Icon(Icons.person, size: avatarRadius * 1.2, color: Colors.blueGrey)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Name with a subtle shadow
                    Text(
                      customerDisplayName,
                      textAlign: TextAlign.left,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: math.max(18.0, dim * 0.05),
                        fontWeight: FontWeight.w700,
                        color: nameColor,
                        shadows: [
                          Shadow(
                            color: Colors.white.withOpacity(0.8),
                            blurRadius: 3,
                            offset: const Offset(0, 0),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// Simple local store: saves templates and exports inside app documents
class _PosterTemplateStore {
  Future<Directory> _templatesDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'poster_templates'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _exportsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'poster_exports'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<File>> listTemplates() async {
    final dir = await _templatesDir();
    final entries = await dir.list().toList();
    final files = entries.whereType<File>().where((f) {
      final ext = p.extension(f.path).toLowerCase();
      return ['.jpg', '.jpeg', '.png', '.webp'].contains(ext);
    }).toList();

    // Sort: latest first
    files.sort((a, b) {
      final am = a.statSync().modified;
      final bm = b.statSync().modified;
      return bm.compareTo(am);
    });
    return files;
  }

  Future<File> addTemplate(File source) async {
    final dir = await _templatesDir();
    final ext = p.extension(source.path).toLowerCase();
    final safeExt = ['.jpg', '.jpeg', '.png', '.webp'].contains(ext) ? ext : '.jpg';
    final name = 'tpl_${DateTime.now().millisecondsSinceEpoch}$safeExt';
    final dest = File(p.join(dir.path, name));
    return source.copy(dest.path);
  }

  Future<void> deleteTemplate(File f) async {
    if (await f.exists()) {
      await f.delete();
    }
  }

  Future<File> saveExport(Uint8List pngBytes) async {
    final dir = await _exportsDir();
    final name = 'poster_${DateTime.now().millisecondsSinceEpoch}.png';
    final out = File(p.join(dir.path, name));
    await out.writeAsBytes(pngBytes, flush: true);
    return out;
  }

  // Copy default assets into templates folder once
  Future<void> ensureDefaultsLoaded() async {
    final prefs = await SharedPreferences.getInstance();
    const flagKey = 'poster_defaults_loaded_v1';
    if (prefs.getBool(flagKey) == true) return;

    final dir = await _templatesDir();

    final defaults = <Map<String, String>>[
      {'asset': 'assets/posters/birthday/b1.jpg', 'name': 'default_bday_1.jpg'},
      {'asset': 'assets/posters/birthday/b2.jpg', 'name': 'default_bday_2.jpg'},
      {'asset': 'assets/posters/anniversary/a1.jpg', 'name': 'default_anniv_1.jpg'},
      {'asset': 'assets/posters/anniversary/a2.jpg', 'name': 'default_anniv_2.jpg'},
    ];

    for (final item in defaults) {
      try {
        final data = await rootBundle.load(item['asset']!);
        final out = File(p.join(dir.path, item['name']!));
        if (!await out.exists()) {
          await out.writeAsBytes(
            data.buffer.asUint8List(),
            flush: true,
          );
        }
      } catch (e) {
        debugPrint('Default poster copy failed for ${item['asset']}: $e');
      }
    }

    await prefs.setBool(flagKey, true);
  }
}