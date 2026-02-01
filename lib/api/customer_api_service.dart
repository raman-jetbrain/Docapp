import 'dart:convert';
import 'dart:typed_data';

import 'package:docapp/api/api_constant.dart';
import 'package:docapp/model/customer.dart' as model;
import 'package:docapp/storage/Token_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class CustomerApiService {
  final String baseUrl = ApiConstants.baseUrl;
  final http.Client _client;
  static const bool _enableHttpLog = true;

  CustomerApiService({http.Client? client}) : _client = client ?? http.Client();

  // Key for storing child customer ids in local storage
  static const String _kChildIdsPrefsKey = 'child_customer_ids';

  // In‑memory cache of child ids (across calls to this instance)
  Set<String> _childCustomerIds = {};

  // ---------------- core helpers ----------------

  Future<String?> _resolveToken() async {
    final dynamic v = TokenStorage.getToken();
    if (v is Future) {
      final dynamic r = await v;
      return r is String ? r : r?.toString();
    }
    return v is String ? v : v?.toString();
  }

  Uri _buildUri(String base, String path) {
    final normalizedBase = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  void _logRequest({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    String? body,
  }) {
    if (!_enableHttpLog) return;
    debugPrint('[HTTP] $method $uri');
    if (headers != null) {
      final logHeaders = Map<String, String>.from(headers);
      if (logHeaders.containsKey('Authorization')) {
        logHeaders['Authorization'] = 'Bearer ***';
      }
      debugPrint('[HTTP] Headers: ${jsonEncode(logHeaders)}');
    }
    if (body != null && body.isNotEmpty) {
      final short = body.length > 1024
          ? '${body.substring(0, 1024)}...<omitted>'
          : body;
      debugPrint('[HTTP] Body: $short');
    }
  }

  void _logResponse(http.Response resp) {
    if (!_enableHttpLog) return;
    debugPrint('[HTTP] <- ${resp.statusCode} ${resp.request?.url}');
    final body = resp.body;
    if (body.length > 2000 || body.contains('FileData')) {
      debugPrint('[HTTP] Response body: <omitted large payload>');
    } else {
      debugPrint('[HTTP] Response body: $body');
    }
  }

  bool _looksLikeUrl(String? s) =>
      s != null && (s.startsWith('http://') || s.startsWith('https://'));

  String _rootBase(String base) => base.toLowerCase().endsWith('/api')
      ? base.substring(0, base.length - 4)
      : base;

  String? _fileNameToUrl(dynamic fileName) {
    if (fileName == null) return null;
    final s = fileName.toString().trim();
    if (s.isEmpty) return null;
    if (_looksLikeUrl(s)) return s;
    try {
      final base = Uri.parse(_rootBase(baseUrl));
      final rel = s.startsWith('/') ? s.substring(1) : s;
      return base.resolve(rel).toString();
    } catch (_) {
      return null;
    }
  }

  Uint8List? _decodeB64Image(dynamic v) {
    if (v == null) return null;
    var s = v.toString().trim();
    if (s.isEmpty) return null;
    final low = s.toLowerCase();
    if (low == 'string' || low.startsWith('<base64:')) return null;

    final commaIndex = s.indexOf(',');
    if (commaIndex != -1 &&
        s.substring(0, commaIndex).toLowerCase().contains('base64')) {
      s = s.substring(commaIndex + 1);
    }
    s = s.replaceAll(RegExp(r'\s'), '');
    try {
      return base64Decode(base64.normalize(s));
    } catch (e) {
      debugPrint('[CustomerApi] base64 decode failed: $e');
      return null;
    }
  }

  int? _readNumericId(Map<String, dynamic> m) {
    const keys = [
      'Id',
      'ID',
      'CustomerId',
      'CustomerID',
      'CustomerDataMId',
      'CustomerDataMID',
      'CustomerDataId',
      'CustomerDataID',
      'id',
    ];
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is int) return v;
      final p = int.tryParse(v.toString());
      if (p != null) return p;
    }
    return null;
  }

  int? _readParentCustomerDataId(Map<String, dynamic> m) {
    final v =
        m['ParentCustomerDataId'] ??
        m['parentCustomerDataId'] ??
        m['ParentId'] ??
        m['parentId'];
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;

    // .NET /Date(…)/ in ms
    final m = RegExp(r'^/Date\((\d+)\)/$').firstMatch(s);
    if (m != null) {
      final ms = int.tryParse(m.group(1)!);
      if (ms != null) {
        return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
      }
    }

    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;

    // simple d-m-y or m-d-y fallbacks
    final parts = s.split(RegExp(r'[-/.\s]'));
    if (parts.length == 3) {
      int? a = int.tryParse(parts[0]);
      int? b = int.tryParse(parts[1]);
      int? c = int.tryParse(parts[2]);
      if (a != null && b != null && c != null) {
        if (a > 12) {
          // d-m-y
          return DateTime.tryParse(
            '${c.toString().padLeft(4, '0')}-${b.toString().padLeft(2, '0')}-${a.toString().padLeft(2, '0')}',
          );
        } else if (b > 12) {
          // m-d-y
          return DateTime.tryParse(
            '${c.toString().padLeft(4, '0')}-${a.toString().padLeft(2, '0')}-${b.toString().padLeft(2, '0')}',
          );
        } else {
          // y-m-d
          if (c > 1900) {
            return DateTime.tryParse(
              '${a.toString().padLeft(4, '0')}-${b.toString().padLeft(2, '0')}-${c.toString().padLeft(2, '0')}',
            );
          }
        }
      }
    }
    return null;
  }

  // ---------------- child-id persistence ----------------

  Future<void> _saveChildIds(Set<String> ids) async {
    _childCustomerIds = ids;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kChildIdsPrefsKey, ids.toList());
    } catch (e) {
      debugPrint('[CustomerApi] failed to save child ids: $e');
    }
  }

  Future<void> _loadChildIdsIfEmpty() async {
    if (_childCustomerIds.isNotEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kChildIdsPrefsKey) ?? const [];
      _childCustomerIds = list.toSet();
    } catch (e) {
      debugPrint('[CustomerApi] failed to load child ids: $e');
    }
  }

  Future<bool> _isChildId(String id) async {
    if (id.isEmpty) return false;
    await _loadChildIdsIfEmpty();
    return _childCustomerIds.contains(id);
  }

  // ---------------- child id extraction ----------------

  Set<String> _extractChildIdsFromRawList(List<dynamic> raw) {
    final out = <String>{};

    for (final item in raw) {
      if (item is! Map) continue;
      final outer = Map<String, dynamic>.from(item);

      // Sometimes real fields are inside 'CustomerData'
      final inner = (outer['CustomerData'] is Map)
          ? Map<String, dynamic>.from(outer['CustomerData'])
          : outer;

      // Mark this row itself as child if ParentCustomerDataId > 0
      void processRowAsPotentialChild(Map<String, dynamic> m) {
        final parentId = _readParentCustomerDataId(m);
        if (parentId != null && parentId > 0) {
          final cid = _readNumericId(m)?.toString();
          if (cid != null && cid.isNotEmpty) {
            out.add(cid);
          }
        }
      }

      processRowAsPotentialChild(inner);
      if (!identical(inner, outer)) {
        processRowAsPotentialChild(outer);
      }

      // Look for child collections: ChildDatas / ChildData / etc.
      dynamic childData =
          outer['ChildDatas'] ??
          outer['childDatas'] ??
          outer['ChildData'] ??
          outer['childData'] ??
          inner['ChildDatas'] ??
          inner['childDatas'] ??
          inner['ChildData'] ??
          inner['childData'];

      void addChildIdFromMap(Map<String, dynamic> cm) {
        final cidNum = _readNumericId(cm);
        String? cid = cidNum?.toString();
        cid ??=
            (cm['ChildId'] ??
                    cm['childId'] ??
                    cm['CustomerId'] ??
                    cm['customerId'])
                ?.toString();
        if (cid != null && cid.isNotEmpty) out.add(cid);
      }

      if (childData is List) {
        for (final c in childData) {
          if (c == null) continue;
          if (c is Map<String, dynamic>) {
            addChildIdFromMap(Map<String, dynamic>.from(c));
          } else {
            final cid = c.toString();
            if (cid.isNotEmpty) out.add(cid);
          }
        }
      } else if (childData is Map<String, dynamic>) {
        addChildIdFromMap(Map<String, dynamic>.from(childData));
      }
    }

    return out;
  }

  // ---------------- response unwrapping helper ----------------

  List<dynamic> _extractCustomerList(dynamic decoded, {String? source}) {
    dynamic payload = decoded;

    if (payload is Map) {
      final wrapper =
          payload['Response'] ??
          payload['response'] ??
          payload['Result'] ??
          payload['result'];
      if (wrapper != null) {
        payload = wrapper;
      }
    }

    if (payload is List) {
      return payload;
    }

    if (payload is Map) {
      dynamic people = payload['People'] ?? payload['people'];
      dynamic data = payload['Data'] ?? payload['data'];

      if (people is List) {
        return List<dynamic>.from(people);
      }
      if (data is List) {
        return List<dynamic>.from(data);
      }

      if (people is Map) {
        return [people];
      }
      if (data is Map) {
        return [data];
      }

      return [payload];
    }

    throw Exception(
      'Unexpected response format'
      '${source != null ? ' from $source' : ''}',
    );
  }

  // ---------------- public API ----------------

  /// Get all customers via /api/CustomerDataM/GetAllAsync.
  ///
  /// Returns ONLY parent customers (children are filtered out).
  Future<List<model.Customer>> getCustomers() async {
    final token = await _resolveToken();
    if (token == null || token.isEmpty) {
      throw Exception('Missing auth token');
    }

    var base = baseUrl.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    if (!base.toLowerCase().endsWith('/api')) base = '$base/api';

    final uri = Uri.parse('$base/CustomerDataM/GetAllAsync');
    final headers = {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };

    _logRequest(method: 'GET', uri: uri, headers: headers);
    final resp = await _client
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 30));
    _logResponse(resp);

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
        'GET ${uri.path} failed: ${resp.statusCode} ${resp.body}',
      );
    }

    final decoded = json.decode(resp.body);
    final list = _extractCustomerList(decoded, source: 'GetAllAsync');

    final childIds = _extractChildIdsFromRawList(list);
    await _saveChildIds(childIds);

    final result = <model.Customer>[];

    for (final e in list) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final effective = (m['CustomerData'] is Map)
          ? Map<String, dynamic>.from(m['CustomerData'])
          : m;

      final customer = _mapApiToCustomer(effective);

      final idStr =
          (customer.id ??
                  customer.serverId ??
                  _readNumericId(effective)?.toString() ??
                  '')
              .toString();

      // Skip children
      if (idStr.isNotEmpty && childIds.contains(idStr)) {
        continue;
      }

      // Also skip records that have ParentCustomerDataId > 0
      final pid = customer.parentCustomerDataId;
      if (pid != null && pid > 0) {
        continue;
      }

      result.add(customer);
    }

    return result;
  }

  /// Get customers via /api/CustomerDataM/GetAsync.
  ///
  /// NO child-id checking/filtering here: it just lists everything.
  Future<List<model.Customer>> getCustomersFromGetAsync() async {
    final token = await _resolveToken();
    if (token == null || token.isEmpty) {
      throw Exception('Missing auth token');
    }

    var base = baseUrl.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    if (!base.toLowerCase().endsWith('/api')) base = '$base/api';

    final uri = Uri.parse('$base/CustomerDataM/GetAsync');
    final headers = {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };

    _logRequest(method: 'GET', uri: uri, headers: headers);
    final resp = await _client
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 30));
    _logResponse(resp);

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
        'GET ${uri.path} failed: ${resp.statusCode} ${resp.body}',
      );
    }

    final decoded = json.decode(resp.body);
    final list = _extractCustomerList(decoded, source: 'GetAsync');

    // No child id extraction / no filtering here
    final result = <model.Customer>[];

    for (final e in list) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final effective = (m['CustomerData'] is Map)
          ? Map<String, dynamic>.from(m['CustomerData'])
          : m;

      final customer = _mapApiToCustomer(effective);
      result.add(customer);
    }

    return result;
  }

  /// GET one customer by id (tries a few likely endpoints).
  ///
  /// Now ALSO works for child ids (no skipping); they will be shown
  /// in the detail page like normal customers.
  Future<model.Customer?> getCustomerById(String id) async {
    final token = await _resolveToken();
    if (token == null || token.isEmpty) throw Exception('Missing auth token');
    if (id.isEmpty) return null;

    // We still log if it's a known child, but we DO NOT skip it.
    final isChild = await _isChildId(id);
    if (isChild) {
      debugPrint(
        '[CustomerApi] getCustomerById($id) is a child record; loading anyway.',
      );
    }

    var base = baseUrl.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    if (!base.toLowerCase().endsWith('/api')) base = '$base/api';

    final headers = {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final candidates = <Uri>[
      Uri.parse('$base/CustomerDataM/GetByIdAsync/$id'),
      Uri.parse('$base/CustomerDataM/GetById/$id'),
      Uri.parse('$base/CustomerDataM/GetAsync/$id'),
      Uri.parse('$base/CustomerDataM/GetById?id=$id'),
      Uri.parse('$base/CustomerDataM/Get/$id'),
    ];

    for (final uri in candidates) {
      try {
        _logRequest(method: 'GET', uri: uri, headers: headers);
        final resp = await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 20));
        _logResponse(resp);
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          final decoded = json.decode(resp.body);
          dynamic item;
          if (decoded is Map) {
            final inner = decoded['Response'] ?? decoded['response'] ?? decoded;
            if (inner is Map) {
              item = inner;
            } else if (inner is List && inner.isNotEmpty) {
              item = inner.first;
            } else {
              item = decoded;
            }
          } else if (decoded is List && decoded.isNotEmpty) {
            item = decoded.first;
          }
          if (item is Map) {
            return _mapApiToCustomer(Map<String, dynamic>.from(item));
          }
        } else if (resp.statusCode == 404) {
          continue;
        }
      } catch (e) {
        debugPrint('[API] getCustomerById($id) via $uri failed: $e');
      }
    }
    return null;
  }

  // Map one API map -> Customer model
  model.Customer _mapApiToCustomer(Map<String, dynamic> m) {
    final id = (_readNumericId(m) ?? (m['Id'] ?? m['id'] ?? '')).toString();

    String first = (m['Name'] ?? '').toString().trim();
    String last = (m['Surname'] ?? '').toString().trim();
    if (last.isEmpty && first.contains(' ')) {
      final parts = first.split(RegExp(r'\s+'));
      first = parts.isNotEmpty ? parts.first : '';
      last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    }

    final phone = (m['PhoneNumber'] ?? '').toString().trim();
    final email = (m['EmailId'] ?? '').toString().trim();
    final address = (m['Address'] ?? '').toString().trim();
    final gender = (m['Gender'] ?? '').toString().trim();
    final othersApi = (m['Others'] ?? '').toString().trim();

    final maritalStatusRaw =
        (m['maritalStatus'] ?? m['MaritalStatus'] ?? m['MartialStatus'])
            ?.toString();
    final marriedDateRaw = (m['marriedDate'] ?? m['MarriedDate'])?.toString();

    Uint8List? bytes;
    String? b64ForModel;
    String? urlFromFileName;
    dynamic fileIdRaw = m['FileId'];

    final httpFile = m['HttpFileData'] ?? m['httpFileData'];
    if (httpFile is Map) {
      final fd = (httpFile['FileData'] ?? httpFile['Data'])?.toString();
      urlFromFileName = _fileNameToUrl(httpFile['FileName']);
      fileIdRaw = fileIdRaw ?? httpFile['Id'] ?? httpFile['FileId'];

      final decoded = _decodeB64Image(fd);
      if (decoded != null && decoded.isNotEmpty) {
        bytes = decoded;
        b64ForModel = base64Encode(decoded);
      }
    } else if (httpFile is String) {
      final decoded = _decodeB64Image(httpFile);
      if (decoded != null && decoded.isNotEmpty) {
        bytes = decoded;
        b64ForModel = base64Encode(decoded);
      }
    }

    if (bytes == null && othersApi.startsWith('data:image')) {
      final decoded = _decodeB64Image(othersApi);
      if (decoded != null && decoded.isNotEmpty) {
        bytes = decoded;
        b64ForModel = base64Encode(decoded);
      }
    }

    final othersForModel =
        (urlFromFileName != null && urlFromFileName.isNotEmpty)
            ? urlFromFileName
            : othersApi;

    final dobRaw =
        m['DOB'] ??
        m['Dob'] ??
        m['dob'] ??
        m['DateOfBirth'] ??
        m['dateOfBirth'] ??
        m['BirthDate'] ??
        m['birthDate'] ??
        m['Birthday'] ??
        m['birthday'];
    final dob = _parseDate(dobRaw);
    final dobIso = dob?.toIso8601String();

    dynamic rawChildren =
        m['Children'] ??
        m['children'] ??
        m['ChildrenNames'] ??
        m['childrenNames'] ??
        m['Kids'] ??
        m['kids'] ??
        m['Dependents'] ??
        m['dependents'];
    dynamic rawChildName =
        m['ChildName'] ?? m['childName'] ?? m['Child'] ?? m['child'];

    List<String> normalizeChildren(dynamic a, dynamic b) {
      final out = <String>[];
      void add(dynamic v) {
        if (v == null) return;
        if (v is List) {
          for (final e in v) {
            final s = e?.toString().trim();
            if (s != null && s.isNotEmpty) out.add(s);
          }
        } else if (v is String) {
          final s = v.trim();
          if (s.isEmpty) return;
          if ((s.startsWith('[') && s.endsWith(']')) ||
              (s.startsWith('"') && s.endsWith('"'))) {
            try {
              final decoded = json.decode(s);
              add(decoded);
              return;
            } catch (_) {}
          }
          s
              .split(RegExp(r'[;,|]'))
              .map((x) => x.trim())
              .where((x) => x.isNotEmpty)
              .forEach(out.add);
        } else {
          final s = v.toString().trim();
          if (s.isNotEmpty) out.add(s);
        }
      }

      add(a);
      add(b);
      final seen = <String>{};
      return out.where((e) => seen.add(e)).toList();
    }

    final childrenList = normalizeChildren(rawChildren, rawChildName);
    final parentId = _readParentCustomerDataId(m);

    final map = <String, dynamic>{
      'id': id,
      'serverId': id,
      'fileId': fileIdRaw,
      'parentCustomerDataId': parentId,
      'name': first,
      'surname': last,
      'phone': phone,
      'email': email,
      'address': address,
      'gender': gender,
      'others': othersForModel,
      'imageBytes': bytes,
      'imageB64': b64ForModel,
      if (dobIso != null) 'dob': dobIso,
      if (maritalStatusRaw != null && maritalStatusRaw.isNotEmpty)
        'maritalStatus': maritalStatusRaw,
      if (marriedDateRaw != null && marriedDateRaw.isNotEmpty)
        'marriedDate': marriedDateRaw,
      if (childrenList.isNotEmpty) 'children': childrenList,
      if (childrenList.length == 1) 'childName': childrenList.first,
    };

    return model.Customer.fromMap(map);
  }

  // ---------------- File download by FileId ----------------

  Future<Uint8List?> fetchFileBytesById(dynamic fileId) async {
    final token = await _resolveToken();
    if (token == null || token.isEmpty) throw Exception('Missing auth token');

    int? fidNum;
    if (fileId is int) {
      fidNum = fileId;
    } else {
      fidNum = int.tryParse(fileId?.toString() ?? '');
    }
    if (fidNum == null || fidNum <= 0) return null;
    final fid = fidNum.toString();

    final headersJson = {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final headersBinary = {'Accept': '*/*', 'Authorization': 'Bearer $token'};

    var base = baseUrl.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    if (!base.toLowerCase().endsWith('/api')) base = '$base/api';

    final candidates = <Uri>[
      Uri.parse('$base/CustomerDataM/GetFile/$fid'),
      Uri.parse('$base/CustomerDataM/GetFile?id=$fid'),
      Uri.parse('$base/CustomerDataM/DownloadFile/$fid'),
      Uri.parse('$base/CustomerDataM/DownloadFile?id=$fid'),
      Uri.parse('$base/File/Download/$fid'),
      Uri.parse('$base/File/Get/$fid'),
    ];

    for (int i = 0; i < candidates.length; i++) {
      final uri = candidates[i];
      final isJsonAttempt = i < 4;
      final headers = isJsonAttempt ? headersJson : headersBinary;

      _logRequest(method: 'GET', uri: uri, headers: headers);
      http.Response resp;
      try {
        resp = await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        debugPrint('[API] GET $uri threw: $e');
        continue;
      }
      _logResponse(resp);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final ctype = (resp.headers['content-type'] ?? '').toLowerCase();

        if (ctype.contains('application/json') || ctype.contains('text/json')) {
          try {
            final decoded = json.decode(resp.body);
            dynamic fileData;
            if (decoded is Map) {
              final inner =
                  decoded['Response'] ?? decoded['response'] ?? decoded;
              if (inner is Map) {
                fileData =
                    inner['FileData'] ??
                    inner['Data'] ??
                    inner['fileData'] ??
                    inner['data'];
              } else if (inner is String) {
                fileData = inner;
              }
              fileData ??=
                  decoded['FileData'] ?? decoded['Data'] ?? decoded['fileData'];
            } else if (decoded is String) {
              fileData = decoded;
            }
            final bytes = _decodeB64Image(fileData);
            if (bytes != null && bytes.isNotEmpty) return bytes;
          } catch (e) {
            debugPrint('[CustomerApi] parse JSON file($fid) failed: $e');
          }
        } else {
          if (resp.bodyBytes.isNotEmpty) return resp.bodyBytes;
        }
      } else if (resp.statusCode == 404 || resp.statusCode == 405) {
        continue;
      } else {
        debugPrint('[API] GET $uri -> ${resp.statusCode} ${resp.reasonPhrase}');
        continue;
      }
    }
    return null;
  }

  Future<model.Customer?> getCustomerByPhone(String s) async {
    // Implement only if you have such an endpoint
    return null;
  }
}