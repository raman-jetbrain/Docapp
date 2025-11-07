import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import 'package:docapp/api/customer_api_service.dart';
import 'package:docapp/model/customer.dart' as model;
import 'package:docapp/postereditpage.dart';

class WeddingAnniversaryPage extends StatefulWidget {
  const WeddingAnniversaryPage({super.key});

  @override
  State<WeddingAnniversaryPage> createState() => _WeddingAnniversaryPageState();
}

class _WeddingAnniversaryPageState extends State<WeddingAnniversaryPage> {
  final _api = CustomerApiService();
  late Future<List<_CustomerWithAnniversary>> _future;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _future = _fetchCustomersWithAnniversaries();
  }

  Future<List<_CustomerWithAnniversary>> _fetchCustomersWithAnniversaries() async {
    final list = await _api.getCustomers();
    return list.map((c) {
      final map = _safeToMap(c);
      final ann = _readAnniversary(map);
      return _CustomerWithAnniversary(customer: c, anniversary: ann);
    }).toList(growable: false);
  }

  Map<String, dynamic> _safeToMap(model.Customer c) {
    try {
      return c.toMap();
    } catch (_) {
      return {};
    }
  }

  static const List<String> _annivKeys = [
    'anniversary', 'Anniversary',
    'anniversaryDate', 'AnniversaryDate',
    'marriageDate', 'MarriageDate',
    'marriedDate', 'MarriedDate',
    'marriedOn', 'MarriedOn',
    'dateOfMarriage', 'DateOfMarriage',
    'weddingDate', 'WeddingDate',
    'doa', 'DOA', 'dom', 'DOM',
  ];

  DateTime? _readAnniversary(Map<String, dynamic> m) {
    final direct = _readDateByKeys(m, _annivKeys);
    if (direct != null) return direct;

    final ce = m['customEntries'];
    if (ce is List) {
      for (final e in ce) {
        if (e is Map) {
          final label = (e['label'] ?? e['name'] ?? e['key'] ?? e['title'] ?? '').toString();
          final val = e.containsKey('value') ? e['value'] : e['val'];
          if (label.isNotEmpty && _looksLikeAnniv(label)) {
            final d = _parseDateFlex(val);
            if (d != null) return d;
          }
        }
      }
    }

    final others = (m['others'] ?? m['Others'])?.toString().trim();
    if (others != null && others.isNotEmpty && !(others.startsWith('http://') || others.startsWith('https://'))) {
      final fromOthers = _readDateFromFreeText(others);
      if (fromOthers != null) return fromOthers;
    }

    return null;
  }

  bool _looksLikeAnniv(String key) {
    final k = key.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    return k.contains('anniver') ||
        k.contains('wedding') ||
        k.contains('marri') ||
        k == 'doa' ||
        k == 'dom' ||
        k.contains('dateofanniversary') ||
        k.contains('dateofmarriage') ||
        k.contains('marriagedate') ||
        k.contains('marrieddate') ||
        k.contains('marriedon') ||
        k.contains('weddingdate');
  }

  DateTime? _readDateByKeys(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      if (!m.containsKey(k) || m[k] == null) continue;
      final dt = _parseDateFlex(m[k]);
      if (dt != null) return dt;
    }
    return null;
  }

  DateTime? _readDateFromFreeText(String text) {
    final reg = RegExp(
      r'(marriage\s*date|married\s*(date|on)|wedding\s*date|doa|dom)\s*[:\-]?\s*([0-9A-Za-z/\-\. ]{4,})',
      caseSensitive: false,
    );
    final m = reg.firstMatch(text);
    if (m == null) return null;
    final raw = (m.group(3) ?? '').trim();
    final cleaned = raw.split(RegExp(r'[^0-9A-Za-z/\-\. ]')).first.trim();
    return _parseDateFlex(cleaned);
  }

  DateTime? _parseDateFlex(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.isUtc ? v.toLocal() : v;

    final s0 = v.toString().trim();
    if (s0.isEmpty || s0.toLowerCase() == 'null') return null;

    final mNet = RegExp(r'^/Date\((\d+)\)/$').firstMatch(s0);
    if (mNet != null) {
      final ms = int.tryParse(mNet.group(1)!);
      if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    }

    if (RegExp(r'^\d+$').hasMatch(s0)) {
      final n = int.tryParse(s0);
      if (n != null) {
        if (s0.length >= 12) return DateTime.fromMillisecondsSinceEpoch(n, isUtc: true).toLocal();
        if (s0.length == 10) return DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true).toLocal();
      }
    }

    final iso = DateTime.tryParse(s0);
    if (iso != null) return iso.isUtc ? iso.toLocal() : iso;

    final s = s0.replaceAll('/', '-').replaceAll('.', '-');
    final parts = s.split('-').where((e) => e.trim().isNotEmpty).toList();

    if (parts.length >= 3) {
      if (parts[0].length == 4) {
        final y = int.tryParse(parts[0]) ?? 0;
        final mm = int.tryParse(parts[1]) ?? 0;
        final dd = int.tryParse(parts[2]) ?? 0;
        if (y > 0 && mm > 0 && dd > 0) return DateTime(y, mm, dd);
      } else {
        final dd = int.tryParse(parts[0]) ?? 0;
        final mm = int.tryParse(parts[1]) ?? 0;
        int y = int.tryParse(parts[2]) ?? 0;
        if (y > 0 && y < 100) y += 2000;
        if (y > 0 && mm > 0 && dd > 0) return DateTime(y, mm, dd);
      }
    }

    if (parts.length == 2) {
      final now = DateTime.now();
      final dd = int.tryParse(parts[0]) ?? 0;
      final mm = int.tryParse(parts[1]) ?? 0;
      if (mm > 0 && dd > 0) return DateTime(now.year, mm, dd);
    }

    final nums = RegExp(r'\d+').allMatches(s0).map((m) => m.group(0)!).toList();
    if (nums.length >= 3 && nums[0].length == 4) {
      final y = int.tryParse(nums[0]) ?? 0;
      final mm = int.tryParse(nums[1]) ?? 0;
      final dd = int.tryParse(nums[2]) ?? 0;
      if (y > 0 && mm > 0 && dd > 0) return DateTime(y, mm, dd);
    } else if (nums.length >= 2) {
      final now = DateTime.now();
      final dd = int.tryParse(nums[0]) ?? 0;
      final mm = int.tryParse(nums[1]) ?? 0;
      if (mm > 0 && dd > 0) return DateTime(now.year, mm, dd);
    }

    return null;
  }

  bool _isLeap(int y) {
    if (y % 400 == 0) return true;
    if (y % 100 == 0) return false;
    return y % 4 == 0;
  }

  bool _matchesMonthDay(DateTime? dt, DateTime on) {
    if (dt == null) return false;
    if (dt.month == 2 && dt.day == 29) {
      return on.month == 2 && (on.day == 29 || (!_isLeap(on.year) && on.day == 28));
    }
    return dt.month == on.month && dt.day == on.day;
  }

  String _formatDate(DateTime d, {bool includeYear = false}) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final base = '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]}';
    return includeYear ? '$base ${d.year}' : base;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wedding Anniversaries'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => setState(() => _future = _fetchCustomersWithAnniversaries()),
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today_outlined),
            tooltip: 'Pick date',
            onPressed: _pickDate,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.pink.withOpacity(0.06),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.favorite, color: Colors.pinkAccent),
                const SizedBox(width: 10),
                Text(
                  'Matches on ${_formatDate(_selectedDate, includeYear: true)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _selectedDate = DateTime.now()),
                  child: const Text('Today'),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<_CustomerWithAnniversary>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                final data = snap.data ?? const [];

                final anniversaries = data.where((c) => _matchesMonthDay(c.anniversary, _selectedDate)).toList();

                if (anniversaries.isEmpty) {
                  return Center(
                    child: Text(
                      'No wedding anniversaries on ${_formatDate(_selectedDate, includeYear: true)}',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  );
                }

                anniversaries.sort((a, b) => ('${a.customer.name} ${a.customer.surname}').toLowerCase()
                    .compareTo(('${b.customer.name} ${b.customer.surname}').toLowerCase()));

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Wedding Anniversaries', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      ...anniversaries.map((cwe) => _CustomerCard(
                        customer: cwe.customer,
                        subtitle: cwe.anniversary != null ? '💍 ${_formatDate(cwe.anniversary!, includeYear: false)}' : null,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PosterSharePage(customer: cwe.customer),
                            ),
                          );
                        },
                      )),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerWithAnniversary {
  final model.Customer customer;
  final DateTime? anniversary;
  const _CustomerWithAnniversary({required this.customer, required this.anniversary});
}

class _CustomerCard extends StatelessWidget {
  final model.Customer customer;
  final String? subtitle;
  final VoidCallback? onTap;

  const _CustomerCard({
    required this.customer,
    this.subtitle,
    this.onTap,
  });

  Uint8List? _safeDecodeB64(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    try {
      var v = s.trim();
      final comma = v.indexOf(',');
      if (comma != -1 && v.substring(0, comma).toLowerCase().contains('base64')) {
        v = v.substring(comma + 1);
      }
      v = v.replaceAll(RegExp(r'\s'), '');
      if (v.toLowerCase() == 'string' || v.startsWith('<base64:')) return null;
      return base64Decode(base64.normalize(v));
    } catch (_) {
      return null;
    }
  }

  bool _looksLikeUrl(String? s) =>
      s != null && (s.startsWith('http://') || s.startsWith('https://'));

  @override
  Widget build(BuildContext context) {
    ImageProvider? avatar;

    if (customer.imageBytes != null && customer.imageBytes!.isNotEmpty) {
      avatar = MemoryImage(customer.imageBytes!);
    }

    if (avatar == null && (customer.imageB64 ?? '').isNotEmpty) {
      final bytes = _safeDecodeB64(customer.imageB64);
      if (bytes != null && bytes.isNotEmpty) avatar = MemoryImage(bytes);
    }

    if (avatar == null && _looksLikeUrl(customer.others)) {
      avatar = NetworkImage(customer.others!);
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
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
              radius: 28,
              backgroundColor: Colors.blue.shade50,
              backgroundImage: avatar,
              child: avatar == null
                  ? const Icon(Icons.person, size: 28, color: Colors.blueGrey)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${customer.name} ${customer.surname}'.trim(),
                    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    customer.phone,
                    style: TextStyle(fontSize: 14.5, color: Colors.grey.shade700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle!,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}