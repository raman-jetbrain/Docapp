// lib/services/customer_api.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:docapp/api/api_constant.dart';
import 'package:http/http.dart' as http;

class CustomerApi {
  final String baseUrl;
  CustomerApi({String? baseUrl}) : baseUrl = baseUrl ?? ApiConstants.baseUrl;

  String get apiBaseWithApi {
    var b = baseUrl.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    if (!b.toLowerCase().endsWith('/api')) b = '$b/api';
    return b;
  }

  String get baseWithoutApi {
    var b = baseUrl.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    if (b.toLowerCase().endsWith('/api')) b = b.substring(0, b.length - 4);
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    return b;
  }

  // ---------- Helpers ----------
  static Map<String, dynamic> unwrapApi(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      final r = raw['Response'];
      if (r is Map<String, dynamic>) return r;
      if (r is List && r.isNotEmpty && r.first is Map) {
        return Map<String, dynamic>.from(r.first as Map);
      }
      return raw;
    }
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return Map<String, dynamic>.from(raw.first as Map);
    }
    return {};
  }

  static String? extractServerError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        if (decoded['message'] is String) return decoded['message'] as String;
        if (decoded['error'] is String) return decoded['error'] as String;
        if (decoded['errors'] is Map) {
          final errors = decoded['errors'] as Map;
          final lines = <String>[];
          for (final entry in errors.entries) {
            final key = entry.key;
            final val = entry.value;
            if (val is List && val.isNotEmpty) {
              lines.add("$key: ${val.join(', ')}");
            } else if (val is String) {
              lines.add("$key: $val");
            }
          }
          if (lines.isNotEmpty) return lines.join('\n');
        }
      }
    } catch (_) {}
    return null;
  }

  // ---------- API calls ----------
  Future<List<dynamic>> getCustomers(String token) async {
    final url = '$apiBaseWithApi/CustomerDataM/GetAsync';
    final res = await http.get(
      Uri.parse(url),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (res.statusCode < 200 || res.statusCode >= 300) return [];
    final decoded = jsonDecode(res.body);
    if (decoded is Map && decoded['Response'] is List) {
      return decoded['Response'] as List;
    }
    if (decoded is List) return decoded;
    return [];
  }

  Future<Map<String, dynamic>> getCustomerById(String token, int id) async {
    final url = '$apiBaseWithApi/CustomerDataM/GetAsync/$id';
    final res = await http.get(
      Uri.parse(url),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(extractServerError(res.body) ?? 'Server error ${res.statusCode}');
    }
    final decoded = jsonDecode(res.body);
    return unwrapApi(decoded);
  }

  Future<List<Map<String, dynamic>>> getDocumentsViaPost(String token, int customerId) async {
    final url = '$apiBaseWithApi/CustomerDataM/FileRecordGetAsync';
    final res = await http.post(
      Uri.parse(url),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        "CustomerDataId": customerId,
        "IncludeDeleted": false,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) return [];

    final decoded = jsonDecode(res.body);
    final payload = unwrapApi(decoded);

    List docs = const [];
    if (payload['Documents'] is List) {
      docs = payload['Documents'] as List;
    } else if (payload['documents'] is List) {
      docs = payload['documents'] as List;
    } else if (payload['Data'] is Map && payload['Data']['Documents'] is List) {
      docs = payload['Data']['Documents'] as List;
    } else if (payload['Data'] is List) {
      docs = payload['Data'] as List;
    } else if (payload['Items'] is List) {
      docs = payload['Items'] as List;
    }

    return docs.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // -------- Update (PUT) - updated to build server payload exactly as required --------
  Future<Map<String, dynamic>> updateCustomer(String token, Map<String, dynamic> raw) async {
    final headers = <String, String>{
      "Content-Type": "application/json; charset=utf-8",
      "Accept": "application/json",
      "Authorization": "Bearer $token",
    };

    // Build the exact server payload shape (normalizes keys, dates, and files)
    final payload = _buildUpdatePayload(raw);

    final candidates = <String>[
      '$apiBaseWithApi/CustomerDataM/UpdateAsync',
      // fallback (some deployments expose controller without /api)
      '${baseUrl.trim().replaceAll(RegExp(r"/+$"), "")}/CustomerDataM/UpdateAsync',
    ];

    http.Response? last;
    for (final url in candidates) {
      try {
        final res = await http.put(Uri.parse(url), headers: headers, body: jsonEncode(payload));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final body = res.body.trim();
          if (body.isEmpty) return {};
          try {
            final decoded = jsonDecode(body);
            return decoded is Map<String, dynamic> ? decoded : {'Response': decoded};
          } catch (_) {
            return {"message": body, "status": res.statusCode};
          }
        }
        last = res;
        if (res.statusCode == 404) continue;
        throw Exception(extractServerError(res.body) ?? 'Server error ${res.statusCode}');
      } catch (_) {}
    }
    if (last != null) {
      throw Exception(extractServerError(last.body) ?? 'Server error ${last.statusCode}');
    }
    throw Exception('No reachable Update endpoint');
  }

  Future<void> deleteCustomer(String token, int id) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };

    final candidates = <String>[
      '$apiBaseWithApi/CustomerDataM/DeleteAsync/$id',
      '${baseUrl.trim().replaceAll(RegExp(r"/+$"), "")}/CustomerDataM/DeleteAsync/$id',
    ];

    http.Response? last;
    for (final url in candidates) {
      try {
        final res = await http.delete(Uri.parse(url), headers: headers);
        if (res.statusCode >= 200 && res.statusCode < 300) return;
        last = res;
        if (res.statusCode == 404) continue;
        throw Exception(extractServerError(res.body) ?? 'Server error ${res.statusCode}');
      } catch (_) {}
    }
    if (last != null) {
      throw Exception(extractServerError(last.body) ?? 'Server error ${last.statusCode}');
    }
    throw Exception('No reachable Delete endpoint');
  }

  Future<bool> deleteDocByDeleteEndpoints(String token, String idStr) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };

    final deleteCandidates = <String>[
      '$apiBaseWithApi/CustomerDataM/FileRecordDeleteAsync/$idStr',
      '$apiBaseWithApi/CustomerDataM/FileRecordDelete/$idStr',
      '$apiBaseWithApi/CustomerDataM/FileRecordDeleteAsync?Id=$idStr',
      '$apiBaseWithApi/CustomerDataM/FileRecordDelete?Id=$idStr',
      '${baseUrl.trim().replaceAll(RegExp(r"/+$"), "")}/CustomerDataM/FileRecordDeleteAsync/$idStr',
      '${baseUrl.trim().replaceAll(RegExp(r"/+$"), "")}/CustomerDataM/FileRecordDelete/$idStr',
    ];

    for (final url in deleteCandidates) {
      try {
        final res = await http.delete(Uri.parse(url), headers: headers);
        if (res.statusCode >= 200 && res.statusCode < 300) return true;
        if (res.statusCode == 404) continue;
      } catch (_) {}
    }
    return false;
  }

  Future<bool> deleteDocByPostEndpoint(String token, {required dynamic id, required int? customerId}) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    final candidates = <String>[
      '$apiBaseWithApi/CustomerDataM/FileRecordDeleteAsync',
      '${baseUrl.trim().replaceAll(RegExp(r"/+$"), "")}/CustomerDataM/FileRecordDeleteAsync',
    ];
    final body = jsonEncode({"Id": id, "CustomerDataId": customerId});
    for (final url in candidates) {
      try {
        final res = await http.post(Uri.parse(url), headers: headers, body: body);
        if (res.statusCode >= 200 && res.statusCode < 300) return true;
      } catch (_) {}
    }
    return false;
  }

  Future<bool> addDocMarkDeleted(String token, Map<String, dynamic> payload) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    final candidates = <String>[
      '$apiBaseWithApi/CustomerDataM/FileRecordAddAsync',
      '${baseUrl.trim().replaceAll(RegExp(r"/+$"), "")}/CustomerDataM/FileRecordAddAsync',
    ];
    final body = jsonEncode(payload);
    for (final url in candidates) {
      try {
        final res = await http.post(Uri.parse(url), headers: headers, body: body);
        if (res.statusCode >= 200 && res.statusCode < 300) return true;
      } catch (_) {}
    }
    return false;
  }

  Future<Uint8List?> fetchBytesWithAuth(String? token, String url) async {
    try {
      final headers = <String, String>{'Accept': '*/*'};
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
      final res = await http.get(Uri.parse(url), headers: headers);
      if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
    } catch (_) {}
    return null;
  }

  // ---------- Normalization helpers for Update payload ----------

  Map<String, dynamic> _buildUpdatePayload(Map<String, dynamic> src) {
    // Core fields (accept uppercase/lowercase aliases)
    final id = _toInt(src['Id'] ?? src['id']);
    final parentId = _toInt(src['ParentCustomerDataId'] ?? src['parentCustomerDataId']);
    final name = _str(src['Name'] ?? src['name']);
    final surname = _str(src['Surname'] ?? src['surname']);
    final phoneNumber = _str(src['PhoneNumber'] ?? src['phone'] ?? src['Phone']);
    final fileId = _toInt(src['FileId'] ?? src['fileId']);
    final emailId = _str(src['EmailId'] ?? src['email'] ?? src['Email']);
    final address = _str(src['Address'] ?? src['address']);
    final gender = _str(src['Gender'] ?? src['gender']);
    final others = _str(src['Others'] ?? src['others']);
    final martialStatus = _str(src['MartialStatus'] ?? src['martialStatus'] ?? src['maritalStatus']);

    // Dates
    final dob = _iso(src['DOB'] ?? src['dob']);
    final sdob = _iso(src['SDOB'] ?? src['sdob']);
    final marriedDate = _iso(
      src['MarriedDate'] ?? src['marriedDate'] ?? src['Anniversary'] ?? src['anniversary'] ?? src['MarriageDate'] ?? src['marriageDate'],
    );

    // HttpFileData (single profile file)
    Map<String, dynamic>? httpFileData;
    final rawHfd = _asMap(src['HttpFileData'] ?? src['httpFileData']);
    if (rawHfd != null) {
      httpFileData = _normalizeFileRecord(rawHfd, defaultCustomerId: id);
    } else {
      // try to build from common fields
      final imageBytes = src['imageBytes'];
      final imageB64 = src['imageB64'] ?? src['ImageB64'];
      final fileName = _str(src['fileName'] ?? src['FileName']) ?? 'profile.png';
      final fileType = _str(src['fileType'] ?? src['FileType']) ?? 'image/png';
      final b64 = _b64(imageBytes ?? imageB64 ?? others);
      if (b64 != null && b64.isNotEmpty) {
        httpFileData = {
          'Id': _toInt(src['HttpFileDataId'] ?? src['fileId'] ?? fileId),
          'IsModified': true,
          'FileData': b64,
          'FileName': fileName,
          'FileType': fileType,
          'Remarks': _str(src['fileRemarks'] ?? src['Remarks']),
          'IsDeleted': false,
          'CustomerDataId': id,
        };
      }
    }

    // Documents array
    List<Map<String, dynamic>>? documents;
    final rawDocs = src['Documents'] ?? src['documents'];
    if (rawDocs is List) {
      documents = rawDocs
          .whereType<dynamic>()
          .map((e) => _normalizeFileRecord(_asMap(e) ?? {}, defaultCustomerId: id))
          .toList();
    }

    // ChildDatas passthrough if provided
    List<dynamic>? childDatas;
    final rawChildren = src['ChildDatas'] ?? src['childDatas'] ?? src['children'] ?? src['Childs'];
    if (rawChildren is List) childDatas = rawChildren;

    // Build final payload and strip nulls
    final out = <String, dynamic>{
      'Id': id,
      'ParentCustomerDataId': parentId,
      'Name': name,
      'Surname': surname,
      'PhoneNumber': phoneNumber,
      'FileId': fileId,
      'EmailId': emailId,
      'Address': address,
      'Gender': gender,
      'Others': others,
      'DOB': dob,
      'SDOB': sdob,
      'MartialStatus': martialStatus, // note: server uses "MartialStatus" (typo kept intentionally)
      'MarriedDate': marriedDate,
      if (httpFileData != null) 'HttpFileData': _removeNulls(httpFileData),
      if (childDatas != null) 'ChildDatas': childDatas,
      if (documents != null) 'Documents': documents.map(_removeNulls).toList(),
    };

    return _removeNulls(out);
  }

  Map<String, dynamic> _normalizeFileRecord(Map<String, dynamic> m, {int? defaultCustomerId}) {
    // Normalize FileData (accept data URLs, raw base64, or bytes in 'bytes')
    final fileData = _b64(m['FileData'] ?? m['fileData'] ?? m['bytes']);
    final fileName = _str(m['FileName'] ?? m['fileName']);
    final fileType = _str(m['FileType'] ?? m['fileType']);
    final id = _toInt(m['Id'] ?? m['id']);
    final isModified = _toBool(m['IsModified'] ?? m['isModified']) ?? (fileData != null);
    final isDeleted = _toBool(m['IsDeleted'] ?? m['isDeleted']) ?? false;
    final remarks = _str(m['Remarks'] ?? m['remarks']);
    final custId = _toInt(m['CustomerDataId'] ?? m['customerDataId'] ?? defaultCustomerId);

    return {
      'Id': id,
      'IsModified': isModified,
      'FileData': fileData,
      'FileName': fileName,
      'FileType': fileType,
      'Remarks': remarks,
      'IsDeleted': isDeleted,
      'CustomerDataId': custId,
    };
  }

  Map<String, dynamic> _removeNulls(Map<String, dynamic> m) {
    final copy = Map<String, dynamic>.from(m);
    copy.removeWhere((k, v) {
      if (v == null) return true;
      if (v is String && v.trim().isEmpty) return true;
      if (v is List && v.isEmpty) return true;
      if (v is Map && v.isEmpty) return true;
      return false;
    });
    return copy;
  }

  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty || s.toLowerCase() == 'null' ? null : s;
  }

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString());
  }

  bool? _toBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    final s = v.toString().toLowerCase().trim();
    if (s == '1' || s == 'true' || s == 'yes') return true;
    if (s == '0' || s == 'false' || s == 'no') return false;
    return null;
  }

  String? _iso(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toUtc().toIso8601String();
    final s0 = v.toString().trim();
    if (s0.isEmpty || s0.toLowerCase() == 'null') return null;

    // .NET /Date(ms)/
    final mNet = RegExp(r'^/Date\((\d+)\)/$').firstMatch(s0);
    if (mNet != null) {
      final ms = int.tryParse(mNet.group(1)!);
      if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();
    }

    // pure digits epoch
    if (RegExp(r'^\d+$').hasMatch(s0)) {
      final n = int.tryParse(s0);
      if (n != null) {
        if (s0.length >= 12) return DateTime.fromMillisecondsSinceEpoch(n, isUtc: true).toIso8601String();
        if (s0.length == 10) return DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true).toIso8601String();
      }
    }

    // ISO or yyyy-MM-dd variants
    final iso = DateTime.tryParse(s0);
    if (iso != null) return iso.toUtc().toIso8601String();

    // dd-MM-yyyy or dd/MM/yyyy
    final s = s0.replaceAll('/', '-').replaceAll('.', '-');
    final parts = s.split('-').where((e) => e.trim().isNotEmpty).toList();
    if (parts.length >= 3) {
      if (parts[0].length == 4) {
        final y = int.tryParse(parts[0]) ?? 0;
        final mm = int.tryParse(parts[1]) ?? 0;
        final dd = int.tryParse(parts[2]) ?? 0;
        if (y > 0 && mm > 0 && dd > 0) {
          return DateTime(y, mm, dd).toUtc().toIso8601String();
        }
      } else {
        final dd = int.tryParse(parts[0]) ?? 0;
        final mm = int.tryParse(parts[1]) ?? 0;
        int y = int.tryParse(parts[2]) ?? 0;
        if (y > 0 && y < 100) y += 2000;
        if (y > 0 && mm > 0 && dd > 0) {
          return DateTime(y, mm, dd).toUtc().toIso8601String();
        }
      }
    }
    return null;
  }

  String? _b64(dynamic v) {
    if (v == null) return null;
    if (v is Uint8List && v.isNotEmpty) {
      return base64Encode(v);
    }
    var s = v.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return null;

    // data URL support: data:image/png;base64,xxxx
    final comma = s.indexOf(',');
    if (comma != -1 && s.substring(0, comma).toLowerCase().contains('base64')) {
      s = s.substring(comma + 1);
    }
    s = s.replaceAll(RegExp(r'\s'), '');
    // quick sanity
    try {
      base64Decode(base64.normalize(s));
      return base64.normalize(s);
    } catch (_) {
      return null;
    }
  }
}