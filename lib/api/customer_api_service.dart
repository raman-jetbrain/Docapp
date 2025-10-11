import 'dart:convert';
import 'dart:typed_data';
import 'package:docapp/api/api_constant.dart';
import 'package:docapp/model/customer.dart' as model;
import 'package:docapp/storage/Token_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;


class CustomerApiService {
  final String baseUrl = ApiConstants.baseUrl;
  final http.Client _client;
  static const bool _enableHttpLog = true;

  CustomerApiService({http.Client? client}) : _client = client ?? http.Client();

  Future<String?> _resolveToken() async {
    final Object maybeFuture = TokenStorage.getToken();
    if (maybeFuture is Future) return await maybeFuture as String?;
    return maybeFuture as String?;
  }

  Uri _buildUri(String base, String path) {
    final normalizedBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  void _logRequest({required String method, required Uri uri, Map<String, String>? headers, String? body}) {
    if (!_enableHttpLog) return;
    debugPrint('[HTTP] $method $uri');
    if (headers != null) {
      final logHeaders = Map<String, String>.from(headers);
      if (logHeaders.containsKey('Authorization')) logHeaders['Authorization'] = 'Bearer ***';
      debugPrint('[HTTP] Headers: ${jsonEncode(logHeaders)}');
    }
    if (body != null && body.isNotEmpty) {
      final short = body.length > 1024 ? '${body.substring(0, 1024)}...<omitted>' : body;
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

  // Helpers
  bool _looksLikeUrl(String? s) => s != null && (s.startsWith('http://') || s.startsWith('https://'));

  // Strip trailing /api to resolve relative FileName URLs against host
  String _rootBase(String base) => base.toLowerCase().endsWith('/api') ? base.substring(0, base.length - 4) : base;

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

  // Decode base64; ignore placeholders like "string" or "<base64:...>"
  Uint8List? _decodeB64Image(dynamic v) {
    if (v == null) return null;
    var s = v.toString().trim();
    if (s.isEmpty) return null;
    final low = s.toLowerCase();
    if (low == 'string' || low.startsWith('<base64:')) return null;

    final commaIndex = s.indexOf(',');
    if (commaIndex != -1 && s.substring(0, commaIndex).toLowerCase().contains('base64')) {
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
    const keys = ['Id','ID','CustomerId','CustomerID','CustomerDataMId','CustomerDataMID','CustomerDataId','CustomerDataID','id'];
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is int) return v;
      final p = int.tryParse(v.toString());
      if (p != null) return p;
    }
    return null;
  }

  // GET customers
  Future<List<model.Customer>> getCustomers() async {
    final token = await _resolveToken();
    if (token == null || token.isEmpty) throw Exception('Missing auth token');

    final uri = _buildUri(baseUrl, '/api/CustomerDataM/GetAsync');
    final headers = {'Accept': 'application/json', 'Authorization': 'Bearer $token'};

    _logRequest(method: 'GET', uri: uri, headers: headers);
    final resp = await _client.get(uri, headers: headers);
    _logResponse(resp);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('GET ${uri.path} failed: ${resp.statusCode} ${resp.body}');
    }

    final decoded = json.decode(resp.body);
    final List<dynamic> list = decoded is Map && decoded['Response'] is List
        ? decoded['Response'] as List
        : (decoded is List ? decoded : const []);

    final customers = list.map((e) => _mapApiToCustomer(Map<String, dynamic>.from(e as Map))).toList();

    // Deduplicate by phone; prefer the one with visual data
    final byPhone = <String, model.Customer>{};
    bool hasVisual(model.Customer c) =>
        (c.imageBytes != null && c.imageBytes!.isNotEmpty) ||
        ((c.imageB64 ?? '').isNotEmpty) ||
        _looksLikeUrl(c.others) ||
        (c.fileId != null && c.fileId.toString().trim().isNotEmpty);

    for (final c in customers) {
      final prev = byPhone[c.phone];
      if (prev == null || (hasVisual(c) && !hasVisual(prev))) {
        byPhone[c.phone] = c;
      }
    }
    return byPhone.values.toList();
  }

  // Map API row -> Customer model and decode HttpFileData.FileData
  model.Customer _mapApiToCustomer(Map<String, dynamic> m) {
    final id = (_readNumericId(m) ?? (m['Id'] ?? m['id'] ?? '')).toString();

    String first = (m['Name'] ?? '').toString().trim();
    String last  = (m['Surname'] ?? '').toString().trim();
    if (last.isEmpty && first.contains(' ')) {
      final parts = first.split(RegExp(r'\s+'));
      first = parts.isNotEmpty ? parts.first : '';
      last  = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    }

    final phone   = (m['PhoneNumber'] ?? '').toString().trim();
    final email   = (m['EmailId'] ?? '').toString().trim();
    final address = (m['Address'] ?? '').toString().trim();
    final gender  = (m['Gender'] ?? '').toString().trim();
    final othersApi = (m['Others'] ?? '').toString().trim();

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

    // Fallback: data URL in Others
    if (bytes == null && othersApi.startsWith('data:image')) {
      final decoded = _decodeB64Image(othersApi);
      if (decoded != null && decoded.isNotEmpty) {
        bytes = decoded;
        b64ForModel = base64Encode(decoded);
      }
    }

    final othersForModel = (urlFromFileName != null && urlFromFileName.isNotEmpty)
        ? urlFromFileName
        : othersApi;

    return model.Customer.fromMap(<String, dynamic>{
      'id': id,
      'serverId': id,
      'fileId': fileIdRaw,
      'name': first,
      'surname': last,
      'phone': phone,
      'email': email,
      'address': address,
      'gender': gender,
      'others': othersForModel,
      'imageBytes': bytes,
      'imageB64': b64ForModel,
    });
  }

  // Fetch real bytes by FileId if GET omitted/placeholder FileData
  Future<Uint8List?> fetchFileBytesById(dynamic fileId) async {
    final token = await _resolveToken();
    if (token == null || token.isEmpty) throw Exception('Missing auth token');
    if (fileId == null) return null;
    final fid = fileId.toString().trim();
    if (fid.isEmpty) return null;

    final headersJson = {'Accept': 'application/json', 'Authorization': 'Bearer $token'};
    final headersBinary = {'Accept': '*/*', 'Authorization': 'Bearer $token'};

    final candidates = <Uri>[
      _buildUri(baseUrl, '/api/CustomerDataM/GetFile/$fid'),
      _buildUri(baseUrl, '/api/CustomerDataM/GetFile?id=$fid'),
      _buildUri(baseUrl, '/api/CustomerDataM/DownloadFile/$fid'),
      _buildUri(baseUrl, '/api/CustomerDataM/DownloadFile?id=$fid'),
      _buildUri(baseUrl, '/api/File/Download/$fid'),
      _buildUri(baseUrl, '/api/File/Get/$fid'),
      _buildUri(baseUrl, '/api/Files/$fid'),
    ];

    for (int i = 0; i < candidates.length; i++) {
      final uri = candidates[i];
      final isJsonAttempt = i < 4;
      final headers = isJsonAttempt ? headersJson : headersBinary;

      _logRequest(method: 'GET', uri: uri, headers: headers);
      final resp = await _client.get(uri, headers: headers);
      _logResponse(resp);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final ctype = (resp.headers['content-type'] ?? '').toLowerCase();

        if (ctype.contains('application/json')) {
          try {
            final decoded = json.decode(resp.body);
            dynamic fileData;
            if (decoded is Map) {
              final inner = decoded['Response'] ?? decoded['response'] ?? decoded;
              if (inner is Map) {
                fileData = inner['FileData'] ?? inner['Data'] ?? inner['fileData'] ?? inner['data'];
              } else if (inner is String) {
                fileData = inner;
              }
              fileData ??= decoded['FileData'] ?? decoded['Data'] ?? decoded['fileData'];
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
        continue;
      }
    }
    return null;
  }

  Future<model.Customer?> getCustomerByPhone(String s) async {
    return null;
  }

  Future<model.Customer?> getCustomerById(String s) async {
    return null;
  }
}

