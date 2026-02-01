import 'dart:convert';
import 'dart:io';

import 'package:docapp/api/api_constant.dart';
import 'package:docapp/model/DocumentsItem.dart' show DocumentItem;
import 'package:docapp/model/customer.dart' as model;
import 'package:docapp/storage/Token_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'; // compute()
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int kMaxUploadBytes = 2 * 1024 * 1024;
const int kRawBudgetForBase64 =
    ((kMaxUploadBytes * 3) ~/ 4) - 8 * 1024;

const bool kLogHttpDocs = true;

// -------- Session-like storage for last shared document --------
const String _kLastDocBase64Key = 'last_doc_b64';
const String _kLastDocMimeKey = 'last_doc_mime';
const String _kLastDocNameKey = 'last_doc_name';
const String _kLastDocUrlKey = 'last_doc_url';

class StoredSessionDoc {
  final Uint8List bytes;
  final String mime;
  final String fileName;
  final String? url;

  const StoredSessionDoc({
    required this.bytes,
    required this.mime,
    required this.fileName,
    this.url,
  });
}

// -------- Logging helpers --------
String _maskTokenDocs(String? v) {
  if (v == null || v.isEmpty) return '';
  final s =
      v.replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '')
          .trim();
  if (s.length <= 8) return 'Bearer ****';
  return 'Bearer ${s.substring(0, 4)}****${s.substring(s.length - 4)}';
}

Object _sanitizeJsonBody(Object body) {
  try {
    if (body is String) {
      final decoded = jsonDecode(body);
      final sanitized = _sanitizeJsonAny(decoded);
      return jsonEncode(sanitized);
    } else if (body is Map || body is List) {
      return jsonEncode(_sanitizeJsonAny(body));
    }
  } catch (_) {}
  return body is String ? body : jsonEncode(body);
}

dynamic _sanitizeJsonAny(dynamic v) {
  if (v is Map) {
    final m = Map<String, dynamic>.from(v);
    if (m.containsKey('FileData')) {
      final fd = m['FileData'];
      final len =
          (fd is String) ? fd.length : (fd is List ? fd.length : 0);
      m['FileData'] = '<omitted $len bytes>';
    }
    m.updateAll((key, value) => _sanitizeJsonAny(value));
    return m;
  } else if (v is List) {
    return v.map(_sanitizeJsonAny).toList();
  }
  return v;
}

void logDocReq({
  required String method,
  required Uri url,
  Map<String, String>? headers,
  Object? body,
}) {
  if (!kLogHttpDocs) return;
  final h = {...?headers};
  if (h.containsKey('Authorization')) {
    h['Authorization'] = _maskTokenDocs(h['Authorization']);
  }
  debugPrint('[DOC $method] $url');
  debugPrint('[DOC] Headers: ${jsonEncode(h)}');
  if (body != null) {
    final sanitized = _sanitizeJsonBody(body);
    final s = sanitized is String ? sanitized : sanitized.toString();
    final trimmed =
        s.length > 2000 ? '${s.substring(0, 2000)}...(${s.length} chars)' : s;
    debugPrint('[DOC] Body: $trimmed');
  }
}

void logDocRes(http.Response res) {
  if (!kLogHttpDocs) return;
  final url = res.request?.url;
  final status = res.statusCode;
  final ct = res.headers['content-type']?.toLowerCase() ?? '';
  debugPrint('[DOC <-] $status $url');
  if (ct.contains('application/json') || ct.contains('text/')) {
    final body = res.body;
    final trimmed =
        body.length > 2000 ? '${body.substring(0, 2000)}...(${body.length} chars)' : body;
    debugPrint('[DOC] Response body: $trimmed');
  } else {
    debugPrint('[DOC] Response bytes: ${res.bodyBytes.length} '
        '(${ct.isEmpty ? 'unknown content-type' : ct})');
  }
}

// -------- API helpers --------
String get _apiBaseNormalized {
  var b = ApiConstants.baseUrl.trim();
  if (b.endsWith('/')) b = b.substring(0, b.length - 1);
  if (!b.toLowerCase().endsWith('/api')) b = '$b/api';
  return b;
}

String _resolveFileUrl(String fileNameOrUrl) {
  final u = (fileNameOrUrl).trim();
  if (u.isEmpty) return u;
  if (u.startsWith('http')) return u;
  var base = ApiConstants.baseUrl.trim();
  if (base.endsWith('/')) base = base.substring(0, base.length - 1);
  if (base.toLowerCase().endsWith('/api')) {
    base = base.substring(0, base.length - 4);
  }
  if (u.startsWith('/')) return '$base$u';
  return '$base/$u';
}

String? _extractServerError(String body) {
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
          }
          if (val is String) {
            lines.add("$key: $val");
          }
        }
        if (lines.isNotEmpty) return lines.join('\n');
      }
    }
  } catch (_) {}
  return null;
}

Map<String, dynamic> _unwrapApiPayload(dynamic raw) {
  if (raw is Map<String, dynamic>) {
    final r = raw['Response'];
    if (r is Map<String, dynamic>) return r;
    if (r is List && r.isNotEmpty && r.first is Map<String, dynamic>) {
      return Map<String, dynamic>.from(r.first as Map);
    }
    return raw;
  }
  if (raw is List && raw.isNotEmpty && raw.first is Map<String, dynamic>) {
    return Map<String, dynamic>.from(raw.first as Map);
  }
  return {};
}

// -------- delete flag helpers --------
bool parseBoolLoose(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }
  return false;
}

// Flexible checker: supports IsDeleted / isDeleted / IsDelete / isDelete / IdDelete / idDelete
bool isDeletedFlag(dynamic source) {
  if (source is Map) {
    final m = Map<String, dynamic>.from(source);
    final v = m['IsDeleted'] ??
        m['isDeleted'] ??
        m['IsDelete'] ??
        m['isDelete'] ??
        m['IdDelete'] ??
        m['idDelete'];
    return parseBoolLoose(v);
  }
  return parseBoolLoose(source);
}

// Wrapper that hides the child when deleted
Widget hideIfDeleted({
  required dynamic deletedSource,
  required Widget child,
}) {
  return isDeletedFlag(deletedSource) ? const SizedBox.shrink() : child;
}

// -------- Image/base64 off-main-isolate helpers --------
Future<Uint8List?> compressImageToBudgetIsolate(
    Map<String, dynamic> args) async {
  final bytes = args['bytes'] as Uint8List;
  final budget = args['budget'] as int;
  final minDim = (args['minDim'] as int?) ?? 640;
  final preferJpeg = (args['preferJpeg'] as bool?) ?? true;

  img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  try {
    decoded = img.bakeOrientation(decoded);
  } catch (_) {}

  img.Image working = decoded!;
  int quality = 85;

  while (true) {
    Uint8List out = Uint8List.fromList(
      preferJpeg
          ? img.encodeJpg(working, quality: quality)
          : img.encodePng(working, level: 6),
    );
    if (out.length <= budget) return out;

    if (preferJpeg && quality > 55) {
      quality -= 10;
      continue;
    }

    if (working.width > minDim || working.height > minDim) {
      final newW = (working.width * 0.85).round();
      final newH = (working.height * 0.85).round();
      if (newW <= 0 || newH <= 0) return null;
      working = img.copyResize(
        working,
        width: newW,
        height: newH,
        interpolation: img.Interpolation.linear,
      );
      if (preferJpeg) quality = (quality + 5).clamp(55, 85);
      continue;
    }

    if (!preferJpeg) {
      out = Uint8List.fromList(img.encodePng(working, level: 9));
      if (out.length <= budget) return out;
    }
    return null;
  }
}

String base64EncodeIsolate(Uint8List data) => base64Encode(data);

// -------- Doc meta (for delete) --------
class _DocMeta {
  final int recordId; // server record id used for update/delete
  final String fileName;
  final String fileType;
  final String remarks;
  final String? url;
  const _DocMeta({
    required this.recordId,
    required this.fileName,
    required this.fileType,
    required this.remarks,
    this.url,
  });
}

// ---------------- Page ----------------
class DocumentsPage extends StatefulWidget {
  final model.Customer customer;

  const DocumentsPage({super.key, required this.customer});

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  final TextEditingController _typeCtrl = TextEditingController();

  // Pending rows created by "Add" (UI-only)
  final List<DocumentItem> _pending = [];

  // Server documents
  final List<DocumentItem> _serverDocs = [];

  // Server meta for delete
  final Map<String, _DocMeta> _docMetaById = {};

  // delete flag per doc id (for wrapper)
  final Map<String, bool> _deletedById = {};

  String? _selectedId;
  bool _loading = false;

  Color get brandBlue => const Color(0xFF38B6E4);
  Color get borderColor => Colors.black;
  Color get iconColor => Colors.black;

  @override
  void initState() {
    super.initState();
    _refreshFromServer();
  }

  @override
  void dispose() {
    _typeCtrl.dispose();
    super.dispose();
  }

  int? _customerDataId() {
    final sid = widget.customer.serverId;
    if (sid != null && sid.isNotEmpty) {
      final v = int.tryParse(sid);
      if (v != null) return v;
    }
    try {
      final m = widget.customer.toMap();
      final v = m['Id'] ??
          m['id'] ??
          m['CustomerDataId'] ??
          m['CustomerId'];
      if (v is int) return v;
      if (v is String) return int.tryParse(v);
    } catch (_) {}
    return null;
  }

  bool _asBool(dynamic v) => parseBoolLoose(v);

  Future<void> _refreshFromServer() async {
    final id = _customerDataId();
    if (id == null) {
      _snack('Customer id not found');
      return;
    }
    setState(() => _loading = true);
    try {
      final token = await TokenStorage.getToken();
      final headers = <String, String>{
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty)
          'Authorization': 'Bearer $token',
      };
      final uri =
          Uri.parse('$_apiBaseNormalized/CustomerDataM/GetAsync/$id');

      logDocReq(method: 'GET', url: uri, headers: headers);
      final res = await http.get(uri, headers: headers);
      logDocRes(res);

      if (res.statusCode < 200 || res.statusCode >= 300) {
        final msg =
            _extractServerError(res.body) ?? 'HTTP ${res.statusCode}';
        _snack('Fetch failed: $msg');
        return;
      }
      final decoded = jsonDecode(res.body);
      final payload = _unwrapApiPayload(decoded);

      List docs = const [];
      if (payload['Documents'] is List) {
        docs = payload['Documents'] as List;
      } else if (payload['documents'] is List) {
        docs = payload['documents'] as List;
      } else if (payload['Data'] is Map &&
          (payload['Data']['Documents'] is List)) {
        docs = payload['Data']['Documents'] as List;
      }

      final mapped = <DocumentItem>[];
      _docMetaById.clear();
      _deletedById.clear();

      for (final e in docs) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);

        final del = _asBool(
          m['IsDeleted'] ??
              m['isDeleted'] ??
              m['IsDelete'] ??
              m['isDelete'] ??
              m['IdDelete'] ??
              m['idDelete'],
        );

        final idStrRaw = (m['Id'] ?? m['id'] ?? '').toString();
        final recId = int.tryParse(idStrRaw) ?? 0;

        final remarks =
            (m['Remarks'] ?? m['remarks'] ?? '').toString().trim();
        final fileName =
            (m['FileName'] ?? m['fileName'] ?? '').toString().trim();
        final fileType = (m['FileType'] ?? m['fileType'] ?? '').toString();
        final urlRaw =
            (m['Url'] ?? m['url'] ?? fileName).toString();
        final url = urlRaw.isNotEmpty ? _resolveFileUrl(urlRaw) : null;

        String itemTitle =
            remarks.isNotEmpty ? remarks : (fileName.isNotEmpty ? fileName : 'Document');

        final docId = idStrRaw.isEmpty
            ? 'srv_${DateTime.now().microsecondsSinceEpoch}'
            : idStrRaw;

        _deletedById[docId] = del;

        if (del) continue;

        mapped.add(
          DocumentItem(
            id: docId,
            title: itemTitle,
            localPath: null,
            remoteUrl: url,
            mimeType: fileType.isEmpty ? null : fileType,
          ),
        );

        _docMetaById[docId] = _DocMeta(
          recordId: recId,
          fileName: fileName.isNotEmpty
              ? fileName
              : (url != null
                  ? p.basename(Uri.parse(url).path)
                  : 'doc_$docId'),
          fileType: fileType.isNotEmpty
              ? fileType
              : _guessMimeFromExt(
                  fileName.isNotEmpty
                      ? p.extension(fileName)
                      : (url != null
                          ? p.extension(Uri.parse(url).path)
                          : ''),
                ),
          remarks: remarks.isNotEmpty ? remarks : itemTitle,
          url: url,
        );
      }
      setState(() {
        _serverDocs
          ..clear()
          ..addAll(mapped);
        _selectedId = null;
      });
    } catch (e) {
      _snack('Fetch failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ------------- Add Type -> container -------------
  Future<void> _addType() async {
    final t = _typeCtrl.text.trim();
    if (t.isEmpty) {
      _snack('Please enter a type name');
      return;
    }
    setState(() {
      _pending.insert(
        0,
        DocumentItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: t,
        ),
      );
    });
    _typeCtrl.clear();
  }

  // ------------- Blocking progress dialog wrapper -------------
  Future<T> _runBlocking<T>(
      String message, Future<T> Function() task) async {
    BuildContext? dialogCtx;
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) {
        dialogCtx = ctx;
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            content: Row(
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(message)),
              ],
            ),
          ),
        );
      },
    );
    try {
      return await task();
    } finally {
      if (dialogCtx != null &&
          Navigator.of(dialogCtx!).canPop()) {
        Navigator.of(dialogCtx!).pop();
      }
    }
  }

  Future<Uint8List?> _compressImageToUnderLimit(
      Uint8List input) {
    return compute(compressImageToBudgetIsolate, {
      'bytes': input,
      'budget': kRawBudgetForBase64,
      'minDim': 640,
      'preferJpeg': true,
    });
  }

  Future<String> _base64InBackground(Uint8List bytes) =>
      compute(base64EncodeIsolate, bytes);

  // ------------- File signature helpers (basic) -------------
  String _extFromMagic(Uint8List data) {
    if (data.length >= 4) {
      if (data[0] == 0x25 &&
          data[1] == 0x50 &&
          data[2] == 0x44 &&
          data[3] == 0x46) {
        return '.pdf';
      }
      if (data[0] == 0x89 &&
          data[1] == 0x50 &&
          data[2] == 0x4E &&
          data[3] == 0x47) {
        return '.png';
      }
      if (data[0] == 0xFF && data[1] == 0xD8) return '.jpg';
      if (data[0] == 0x47 &&
          data[1] == 0x49 &&
          data[2] == 0x46 &&
          data[3] == 0x38) {
        return '.gif';
      }
      if (data.length >= 12 &&
          data[0] == 0x52 &&
          data[1] == 0x49 &&
          data[2] == 0x46 &&
          data[3] == 0x46 &&
          data[8] == 0x57 &&
          data[9] == 0x45 &&
          data[10] == 0x42 &&
          data[11] == 0x50) {
        return '.webp';
      }
      if (data[0] == 0x50 && data[1] == 0x4B) return '.zip';
    }
    return '';
  }

  // ------------- Pick -> confirm preview -> compress -> upload -------------
  Future<void> _pickAndUpload(DocumentItem d) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return;

    final f = result.files.first;
    final name = f.name;
    String ext = p.extension(name).toLowerCase();
    Uint8List? data = f.bytes;
    if (data == null) {
      _snack('Could not read selected file');
      return;
    }

    if (ext.isEmpty) {
      final magicExt = _extFromMagic(data);
      if (magicExt.isNotEmpty) ext = magicExt;
    }

    bool isImage = _isImageExt(ext);
    if (!isImage) {
      try {
        final decoded = img.decodeImage(data);
        isImage = decoded != null;
      } catch (_) {}
    }

    if (isImage) {
      final confirmed = await _confirmDialog(
        title: 'Upload image?',
        fileName: name,
        sizeBytes: data.length,
        previewBytes: data,
        previewCacheWidth: 800,
      );
      if (!confirmed) return;

      final optimized = await _runBlocking<Uint8List?>(
          'Optimizing image...', () => _compressImageToUnderLimit(data));
      if (optimized == null || optimized.isEmpty) {
        _snack('Image too large or unsupported. Pick a smaller image.');
        return;
      }

      await _uploadToServer(
        remarks: d.title,
        bytes: optimized,
        fileName:
            'doc_${DateTime.now().millisecondsSinceEpoch}.jpg',
        mime: 'image/jpeg',
        pending: d,
      );
    } else {
      if (data.length > kRawBudgetForBase64) {
        _snack('File exceeds limit (~1.5MB raw). Choose a smaller file.');
        return;
      }

      final confirmed = await _confirmDialog(
        title: 'Upload file?',
        fileName: name,
        sizeBytes: data.length,
        previewBytes: null,
      );
      if (!confirmed) return;

      await _uploadToServer(
        remarks: d.title,
        bytes: data,
        fileName: ext.isNotEmpty
            ? name
            : 'file_${DateTime.now().millisecondsSinceEpoch}.bin',
        mime: _guessMimeFromExt(
            ext.isNotEmpty ? ext : '.bin'),
        pending: d,
      );
    }
  }

  Future<void> _uploadToServer({
    required String remarks,
    required Uint8List bytes,
    required String fileName,
    required String mime,
    required DocumentItem pending,
  }) async {
    final cid = _customerDataId();
    if (cid == null) {
      _snack('Customer id not found');
      return;
    }
    if (bytes.length > kRawBudgetForBase64) {
      _snack('File too large for upload after base64 expansion.');
      return;
    }

    try {
      final token = await TokenStorage.getToken();
      final headers = <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty)
          'Authorization': 'Bearer $token',
      };

      await _runBlocking('Uploading...', () async {
        final b64 = await _base64InBackground(bytes);
        final payload = <String, dynamic>{
          "Id": 0,
          "IsModified": true,
          "FileData": b64,
          "FileName": fileName,
          "FileType": mime,
          "Remarks": remarks,
          "IsDeleted": false,
          "CustomerDataId": cid,
        };

        final url = Uri.parse(
            '$_apiBaseNormalized/CustomerDataM/FileRecordAddAsync');

        final bodyStr = jsonEncode(payload);
        logDocReq(
            method: 'POST',
            url: url,
            headers: headers,
            body: bodyStr);
        final res =
            await http.post(url, headers: headers, body: bodyStr);
        logDocRes(res);

        if (res.statusCode < 200 || res.statusCode >= 300) {
          final msg =
              _extractServerError(res.body) ?? 'HTTP ${res.statusCode}';
          throw Exception(msg);
        }
      });

      _snack('Uploaded "$remarks"');
      if (mounted) {
        setState(() {
          _pending.removeWhere((x) => x.id == pending.id);
        });
      }
      await _refreshFromServer();
    } catch (e) {
      _snack('Upload failed: $e');
    }
  }

  // ------------- Delete (IsDeleted = true via FileRecordUpdateAsync) -------------
  Future<void> _deleteDoc(DocumentItem d) async {
    final cid = _customerDataId();
    if (cid == null) {
      _snack('Customer id not found');
      return;
    }

    final meta = _docMetaById[d.id];
    final recId = meta?.recordId ?? int.tryParse(d.id) ?? 0;
    if (recId <= 0) {
      _snack('Document id not found');
      return;
    }

    final fileName = meta?.fileName ??
        (d.remoteUrl != null
            ? p.basename(Uri.parse(d.remoteUrl!).path)
            : 'doc_${d.id}');
    final fileType = meta?.fileType ??
        (d.mimeType ?? _guessMimeFromExt(p.extension(fileName)));
    final remarks = meta?.remarks ?? d.title;

    try {
      final token = await TokenStorage.getToken();
      final headers = <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty)
          'Authorization': 'Bearer $token',
      };

      await _runBlocking('Deleting...', () async {
        final payload = {
          "Id": recId,
          "IsModified": true,
          "FileName": fileName,
          "FileType": fileType,
          "Remarks": remarks,
          "IsDeleted": true,
          "CustomerDataId": cid,
        };

        final url = Uri.parse(
            '$_apiBaseNormalized/CustomerDataM/FileRecordUpdateAsync');

        final bodyStr = jsonEncode(payload);
        logDocReq(
            method: 'POST',
            url: url,
            headers: headers,
            body: bodyStr);
        final res =
            await http.post(url, headers: headers, body: bodyStr);
        logDocRes(res);

        if (res.statusCode < 200 || res.statusCode >= 300) {
          final msg =
              _extractServerError(res.body) ?? 'HTTP ${res.statusCode}';
          throw Exception(msg);
        }
      });

      if (!mounted) return;
      _deletedById[d.id] = true;
      setState(() {
        _serverDocs.removeWhere((x) => x.id == d.id);
        _docMetaById.remove(d.id);
        if (_selectedId == d.id) _selectedId = null;
      });
      _snack('Deleted');
    } catch (e) {
      _snack('Delete failed: $e');
    }
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  // ------------- Confirm dialog -------------
  Future<bool> _confirmDialog({
    required String title,
    required String fileName,
    required int sizeBytes,
    Uint8List? previewBytes,
    int? previewCacheWidth,
  }) async {
    final sizeStr = _fmtSize(sizeBytes);
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          useRootNavigator: true,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (previewBytes != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      previewBytes,
                      height: 180,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      cacheWidth: previewCacheWidth,
                    ),
                  )
                else
                  Container(
                    height: 120,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F3F4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.insert_drive_file_rounded,
                          size: 48,
                          color: Colors.black54,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  sizeStr,
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: brandBlue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Upload'),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ------------- Open / Download / Share -------------
  Future<String?> _ensureLocalFile(DocumentItem d) async {
    if (d.localPath != null &&
        await File(d.localPath!).exists()) {
      return d.localPath;
    }
    if (d.remoteUrl == null) return null;

    try {
      final token = await TokenStorage.getToken();
      final headers = {
        'Accept': '*/*',
        if (token != null && token.isNotEmpty)
          'Authorization': 'Bearer $token',
      };
      final uri = Uri.parse(d.remoteUrl!);

      logDocReq(method: 'GET', url: uri, headers: headers);
      final res = await http.get(uri, headers: headers);
      logDocRes(res);

      if (res.statusCode == 200) {
        final dir = await getApplicationDocumentsDirectory();
        final ext = _extFromUrl(d.remoteUrl!);
        final file = File(
          p.join(
            dir.path,
            'dl_${d.id}_${DateTime.now().millisecondsSinceEpoch}$ext',
          ),
        );
        await file.writeAsBytes(res.bodyBytes);
        d.localPath = file.path;
        d.mimeType ??= _guessMimeFromExt(ext);
        return d.localPath;
      } else {
        _snack('Download failed: HTTP ${res.statusCode}');
      }
    } catch (e) {
      _snack('Download failed: $e');
    }
    return null;
  }

  Future<void> _share(DocumentItem d) async {
    // 1. Ensure document is read from URL and is available locally
    final local = await _ensureLocalFile(d);
    if (local == null) {
      _snack('No file to share');
      return;
    }

    // 2. Save into "session storage" in base64 + meta
    await saveDocToSession(
      filePath: local,
      remoteUrl: d.remoteUrl,
    );

    // 3. Read back from session and share that stored format
    final stored = await readDocFromSession();
    if (stored != null) {
      final xFile = XFile.fromData(
        stored.bytes,
        mimeType: stored.mime,
        name: stored.fileName,
      );
      await Share.shareXFiles(
        [xFile],
        text: stored.url ?? d.title,
      );
    } else {
      // Fallback: share local file directly
      await Share.shareXFiles([XFile(local)], text: d.title);
    }
  }

  Future<void> _download(DocumentItem d) async {
    final local = await _ensureLocalFile(d);
    if (local == null) {
      _snack('Nothing to download yet');
      return;
    }
    final savedPath = await saveToDownloadsFolder(local);
    if (savedPath == null) {
      _snack('Could not save file');
    } else {
      _snack('Saved to $savedPath');
    }
  }

  void _open(DocumentItem d) async {
    final local = await _ensureLocalFile(d);
    if (local == null) return;

    final mime =
        d.mimeType ?? _guessMimeFromExt(p.extension(local));
    if (mime.startsWith('image/')) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ImageViewerScreen(
            path: local,
            title: d.title,
            remoteUrl: d.remoteUrl,
          ),
        ),
      );
    } else if (mime == 'application/pdf' ||
        p.extension(local).toLowerCase() == '.pdf') {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(
            path: local,
            title: d.title,
            remoteUrl: d.remoteUrl,
          ),
        ),
      );
    } else {
      await OpenFilex.open(local);
    }
  }

  // ------------- Utils -------------
  static String _extFromUrl(String url) {
    final u = Uri.tryParse(url);
    final path = u?.path ?? url;
    final ext = p.extension(path);
    return ext.isEmpty ? '' : ext;
  }

  static String _guessMimeFromExt(String ext) {
    final e = ext.toLowerCase();
    if (e == '.png') return 'image/png';
    if (e == '.jpg' || e == '.jpeg') return 'image/jpeg';
    if (e == '.gif') return 'image/gif';
    if (e == '.webp') return 'image/webp';
    if (e == '.bmp') return 'image/bmp';
    if (e == '.tif' || e == '.tiff') return 'image/tiff';
    if (e == '.pdf') return 'application/pdf';
    if (e == '.doc') return 'application/msword';
    if (e == '.docx') {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (e == '.xls') return 'application/vnd.ms-excel';
    if (e == '.xlsx') {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (e == '.txt') return 'text/plain';
    if (e == '.heic') return 'image/heic';
    return 'application/octet-stream';
  }

  bool _isImageExt(String ext) {
    final e = ext.toLowerCase();
    return [
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.bmp',
      '.tif',
      '.tiff',
      '.heic'
    ].contains(e);
  }

  void _selectForDelete(String id) =>
      setState(() => _selectedId = id);
  void _clearSelection() {
    if (_selectedId != null) {
      setState(() => _selectedId = null);
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));

  bool _looksLikeImage(String s) {
    final lower = s.toLowerCase();
    if (lower.startsWith('image/')) return true;
    final ext = p.extension(lower);
    return [
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.bmp',
      '.tif',
      '.tiff',
      '.heic'
    ].contains(ext);
  }

  // ------------- Build -------------
  Widget _buildEmptyState() {
    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: 60.0, horizontal: 24.0),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.file_copy_outlined,
                size: 60, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No documents available',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a new document type above and upload a file.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final padding = width * 0.05;
    final fieldHeight = 50.0;

    final listCount = _pending.length + _serverDocs.length;

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 80,
            pinned: true,
            backgroundColor: Colors.transparent,
            automaticallyImplyLeading: false,
            titleSpacing: 0,
            title: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back,
                      color: Colors.white),
                  onPressed: () =>
                      Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: _DocsAppBarTitle(
                    customer: widget.customer,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh,
                      color: Colors.white),
                  onPressed: _refreshFromServer,
                  tooltip: 'Refresh',
                ),
              ],
            ),
            flexibleSpace: const DecoratedBox(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage("assets/images/Background2.jpeg"),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Column(
              children: [
                // Add Type field
                Container(
                  height: fieldHeight,
                  margin: EdgeInsets.all(padding),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: borderColor),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        offset: Offset(1, 1),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12),
                          child: TextField(
                            controller: _typeCtrl,
                            style:
                                const TextStyle(color: Colors.black),
                            decoration: const InputDecoration(
                              hintText: 'Type',
                              hintStyle: TextStyle(
                                color: Colors.black54,
                                fontWeight: FontWeight.w600,
                              ),
                              border: InputBorder.none,
                            ),
                            onSubmitted: (_) => _addType(),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: fieldHeight,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: borderColor),
                            foregroundColor: borderColor,
                            shape:
                                const RoundedRectangleBorder(
                              borderRadius: BorderRadius.only(
                                topRight: Radius.circular(11),
                                bottomRight: Radius.circular(11),
                              ),
                            ),
                          ),
                          onPressed: _addType,
                          child: const Text('Add'),
                        ),
                      ),
                    ],
                  ),
                ),

                // Header
                Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: padding),
                  child: Row(
                    children: [
                      Text(
                        'Documents List',
                        style: TextStyle(
                          fontSize: width * 0.045,
                          fontWeight: FontWeight.bold,
                          color: borderColor,
                        ),
                      ),
                      if (_loading) ...[
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2),
                        ),
                      ],
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: Colors.black12,
                  ),
                ),

                if (listCount == 0 && !_loading)
                  _buildEmptyState()
                else
                  ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                        padding, 10, padding, padding),
                    shrinkWrap: true,
                    physics:
                        const NeverScrollableScrollPhysics(),
                    itemCount: listCount,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final isPendingRow =
                          index < _pending.length;
                      final d = isPendingRow
                          ? _pending[index]
                          : _serverDocs[index - _pending.length];
                      final selected = _selectedId == d.id;

                      if (isPendingRow) {
                        // Pending row (always visible)
                        return hideIfDeleted(
                          deletedSource: false,
                          child: _DocCard(
                            title: d.title,
                            borderColor: borderColor,
                            iconColor: iconColor,
                            selected: selected,
                            preview: null,
                            showUpload: true,
                            onTap: () {
                              if (selected) _clearSelection();
                            },
                            onLongPress: () =>
                                _selectForDelete(d.id),
                            onDelete: () {
                              setState(() {
                                _pending.removeWhere(
                                    (x) => x.id == d.id);
                                _selectedId = null;
                              });
                            },
                            onUpload: () => _pickAndUpload(d),
                            onDownload: null,
                            onShare: null,
                            onOpen: null,
                          ),
                        );
                      } else {
                        // Server doc row (hidden if deleted)
                        final looksImage = _looksLikeImage(
                            d.mimeType ?? d.remoteUrl ?? '');
                        final Widget? previewWidget =
                            looksImage && d.remoteUrl != null
                                ? Image.network(
                                    d.remoteUrl!,
                                    height: 160,
                                    fit: BoxFit.cover,
                                  )
                                : null;

                        return hideIfDeleted(
                          deletedSource:
                              _deletedById[d.id] ?? false,
                          child: _DocCard(
                            title: d.title,
                            borderColor: borderColor,
                            iconColor: iconColor,
                            selected: selected,
                            preview: previewWidget,
                            showUpload: false,
                            onTap: () {
                              if (selected) {
                                _clearSelection();
                              } else {
                                _open(d);
                              }
                            },
                            onLongPress: () =>
                                _selectForDelete(d.id),
                            onDelete: () => _deleteDoc(d),
                            onUpload: null,
                            onDownload: () => _download(d),
                            onShare: () => _share(d),
                            onOpen: () => _open(d),
                          ),
                        );
                      }
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -------- Download to device storage helper --------
Future<String?> saveToDownloadsFolder(String sourcePath) async {
  final srcFile = File(sourcePath);
  if (!await srcFile.exists()) return null;

  Directory baseDir;
  if (Platform.isAndroid) {
    baseDir = (await getExternalStorageDirectory()) ??
        await getApplicationDocumentsDirectory();
  } else {
    baseDir = await getApplicationDocumentsDirectory();
  }

  final downloadsDir = Directory(p.join(baseDir.path, 'Downloads'));
  if (!await downloadsDir.exists()) {
    await downloadsDir.create(recursive: true);
  }

  final fileName = p.basename(sourcePath);
  final destPath = p.join(downloadsDir.path, fileName);
  await srcFile.copy(destPath);
  return destPath;
}

// -------- Session store helpers: save/read full document --------
Future<void> saveDocToSession({
  required String filePath,
  String? remoteUrl,
}) async {
  try {
    final bytes = await File(filePath).readAsBytes();
    final b64 = base64Encode(bytes);
    final mime =
        _DocumentsPageState._guessMimeFromExt(p.extension(filePath));
    final name = p.basename(filePath);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastDocBase64Key, b64);
    await prefs.setString(_kLastDocMimeKey, mime);
    await prefs.setString(_kLastDocNameKey, name);
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      await prefs.setString(_kLastDocUrlKey, remoteUrl);
    }
  } catch (e) {
    debugPrint('saveDocToSession failed: $e');
  }
}

Future<StoredSessionDoc?> readDocFromSession() async {
  final prefs = await SharedPreferences.getInstance();
  final b64 = prefs.getString(_kLastDocBase64Key);
  if (b64 == null || b64.isEmpty) return null;

  final mime =
      prefs.getString(_kLastDocMimeKey) ?? 'application/octet-stream';
  final name = prefs.getString(_kLastDocNameKey) ?? 'document';
  final url = prefs.getString(_kLastDocUrlKey);
  try {
    final bytes = base64Decode(b64);
    return StoredSessionDoc(
      bytes: bytes,
      mime: mime,
      fileName: name,
      url: url,
    );
  } catch (e) {
    debugPrint('readDocFromSession failed: $e');
    return null;
  }
}

// ---------------- AppBar title widget ----------------
class _DocsAppBarTitle extends StatelessWidget {
  const _DocsAppBarTitle({required this.customer});
  final model.Customer customer;

  String _initials(String name, String surname) {
    final a = name.trim().isNotEmpty
        ? name.trim()[0].toUpperCase()
        : '';
    final b = surname.trim().isNotEmpty
        ? surname.trim()[0].toUpperCase()
        : '';
    final s = (a + b).trim();
    return s.isEmpty ? '?' : s;
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? imgProvider;
    if (customer.imageBytes != null &&
        customer.imageBytes!.isNotEmpty) {
      imgProvider = MemoryImage(customer.imageBytes!);
    }

    final fullName = customer.name.trim();

    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: Colors.white24,
          backgroundImage: imgProvider,
          child: imgProvider == null
              ? Text(
                  _initials(
                      customer.name, customer.surname),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment:
                MainAxisAlignment.center,
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                fullName.isEmpty ? 'Customer' : fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  shadows: [
                    Shadow(
                      blurRadius: 6,
                      color: Colors.black54,
                      offset: Offset(1, 1),
                    )
                  ],
                ),
              ),
              if (customer.phone.trim().isNotEmpty)
                Text(
                  customer.phone,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    shadows: [
                      Shadow(
                        blurRadius: 6,
                        color: Colors.black54,
                        offset: Offset(1, 1),
                      )
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------- Cards ----------------
class _DocCard extends StatelessWidget {
  const _DocCard({
    required this.title,
    required this.onTap,
    required this.onUpload,
    required this.onDownload,
    required this.onShare,
    required this.onOpen,
    required this.borderColor,
    required this.iconColor,
    required this.selected,
    required this.showUpload,
    required this.preview,
    this.onLongPress,
    this.onDelete,
  });

  final String title;
  final VoidCallback onTap;
  final VoidCallback? onUpload;
  final VoidCallback? onDownload;
  final VoidCallback? onShare;
  final VoidCallback? onOpen;
  final VoidCallback? onLongPress;
  final VoidCallback? onDelete;
  final Color borderColor;
  final Color iconColor;
  final bool selected;
  final bool showUpload;
  final Widget? preview;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? Colors.red : Colors.white;
    final textColor =
        selected ? Colors.white : Colors.black87;
    final border =
        selected ? Colors.red : borderColor;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      shadowColor: Colors.black12,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: 1),
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      if (showUpload && onUpload != null)
                        IconButton(
                          onPressed: onUpload,
                          icon: Icon(
                            Icons.upload_rounded,
                            color: iconColor,
                            size: 24,
                          ),
                          tooltip: 'Upload',
                        ),
                      if (onOpen != null)
                        IconButton(
                          onPressed: onOpen,
                          icon: Icon(
                            Icons.visibility_rounded,
                            color: iconColor,
                            size: 22,
                          ),
                          tooltip: 'Open',
                        ),
                      if (onDownload != null)
                        IconButton(
                          onPressed: onDownload,
                          icon: Icon(
                            Icons.download_rounded,
                            color: iconColor,
                            size: 24,
                          ),
                          tooltip: 'Download',
                        ),
                      if (onShare != null)
                        IconButton(
                          onPressed: onShare,
                          icon: Icon(
                            Icons.share,
                            color: iconColor,
                            size: 22,
                          ),
                          tooltip: 'Share',
                        ),
                      if (selected && onDelete != null)
                        IconButton(
                          onPressed: onDelete,
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.white,
                            size: 24,
                          ),
                          tooltip: 'Delete',
                        ),
                    ],
                  ),
                ],
              ),
              if (preview != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius:
                      BorderRadius.circular(10),
                  child: preview,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- Image viewer ----------------
class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({
    super.key,
    required this.path,
    required this.title,
    this.remoteUrl,
  });

  final String path;
  final String title;
  final String? remoteUrl;

  Future<void> _onShare(BuildContext context) async {
    // 1. Save current viewed image into session
    await saveDocToSession(
      filePath: path,
      remoteUrl: remoteUrl,
    );

    // 2. Read back from session and share stored format
    final stored = await readDocFromSession();
    if (stored != null) {
      final xFile = XFile.fromData(
        stored.bytes,
        mimeType: stored.mime,
        name: stored.fileName,
      );
      await Share.shareXFiles(
        [xFile],
        text: stored.url ?? title,
      );
    } else {
      // fallback
      await Share.shareXFiles(
        [XFile(path)],
        text: title,
      );
    }
  }

  Future<void> _onDownload(BuildContext context) async {
    final savedPath = await saveToDownloadsFolder(path);
    final msg = savedPath == null
        ? 'Could not save file'
        : 'Saved to $savedPath';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF38B6E4),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            onPressed: () => _onDownload(context),
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _onShare(context),
          ),
        ],
      ),
      body: PhotoView(
        backgroundDecoration:
            const BoxDecoration(color: Colors.white),
        imageProvider: FileImage(File(path)),
        minScale: PhotoViewComputedScale.contained,
        maxScale:
            PhotoViewComputedScale.covered * 2.5,
      ),
    );
  }
}

// ---------------- PDF viewer ----------------
class PdfViewerScreen extends StatefulWidget {
  const PdfViewerScreen({
    super.key,
    required this.path,
    required this.title,
    this.remoteUrl,
  });

  final String path;
  final String title;
  final String? remoteUrl;

  @override
  State<PdfViewerScreen> createState() =>
      _PdfViewerScreenState();
}

class _PdfViewerScreenState
    extends State<PdfViewerScreen> {
  late PdfControllerPinch controller;

  @override
  void initState() {
    super.initState();
    controller = PdfControllerPinch(
      document: PdfDocument.openFile(widget.path),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _onShare() async {
    await saveDocToSession(
      filePath: widget.path,
      remoteUrl: widget.remoteUrl,
    );

    final stored = await readDocFromSession();
    if (stored != null) {
      final xFile = XFile.fromData(
        stored.bytes,
        mimeType: stored.mime,
        name: stored.fileName,
      );
      await Share.shareXFiles(
        [xFile],
        text: stored.url ?? widget.title,
      );
    } else {
      await Share.shareXFiles(
        [XFile(widget.path)],
        text: widget.title,
      );
    }
  }

  Future<void> _onDownload() async {
    final savedPath =
        await saveToDownloadsFolder(widget.path);
    final msg = savedPath == null
        ? 'Could not save file'
        : 'Saved to $savedPath';
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: const Color(0xFF38B6E4),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            onPressed: _onDownload,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _onShare,
          ),
        ],
      ),
      body: PdfViewPinch(controller: controller),
    );
  }
}