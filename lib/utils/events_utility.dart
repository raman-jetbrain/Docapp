import 'package:docapp/model/customer.dart' as model;

class BirthdayUtils {
  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;

    final m = RegExp(r'^/Date\((\d+)\)/$').firstMatch(s);
    if (m != null) {
      final ms = int.tryParse(m.group(1)!);
      if (ms != null) {
        return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
      }
    }

    final iso = DateTime.tryParse(s);
    if (iso != null) return iso.toLocal();

    final parts = s.split(RegExp(r'[-/.\s]'));
    if (parts.length == 3) {
      int? a = int.tryParse(parts[0]);
      int? b = int.tryParse(parts[1]);
      int? c = int.tryParse(parts[2]);
      if (a != null && b != null && c != null) {
        if (a > 12) {
          return DateTime.tryParse(
              '${c.toString().padLeft(4, '0')}-${b.toString().padLeft(2, '0')}-${a.toString().padLeft(2, '0')}');
        } else if (b > 12) {
          return DateTime.tryParse(
              '${c.toString().padLeft(4, '0')}-${a.toString().padLeft(2, '0')}-${b.toString().padLeft(2, '0')}');
        } else {
          if (c > 1900) {
            return DateTime.tryParse(
                '${a.toString().padLeft(4, '0')}-${b.toString().padLeft(2, '0')}-${c.toString().padLeft(2, '0')}');
          }
        }
      }
    }
    return null;
  }

  static DateTime? dobFromCustomer(model.Customer c) {
    Map<String, dynamic> m;
    try {
      m = c.toMap();
    } catch (_) {
      m = {};
    }

    dynamic dobRaw = m['dob'] ??
        m['DOB'] ??
        m['DateOfBirth'] ??
        m['dateOfBirth'] ??
        m['BirthDate'] ??
        m['birthDate'] ??
        m['Birthday'] ??
        m['birthday'];

    DateTime? dob;
    if (dobRaw != null) dob = _parseDate(dobRaw);
    if (dob == null && dobRaw is String) {
      final tryIso = DateTime.tryParse(dobRaw);
      if (tryIso != null) dob = tryIso.toLocal();
    }
    return dob;
  }

  static bool isBirthdayToday(model.Customer c, {DateTime? now}) {
    final dob = dobFromCustomer(c);
    if (dob == null) return false;
    final today = (now ?? DateTime.now());
    return dob.month == today.month && dob.day == today.day;
  }
}