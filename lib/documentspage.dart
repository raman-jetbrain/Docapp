import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:docapp/api/api_constant.dart';
import 'package:docapp/model/DocumentsItem.dart' show DocumentItem;
import 'package:docapp/model/customer.dart' as model;
import 'package:docapp/storage/Token_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:photo_view/photo_view.dart';
import 'package:share_plus/share_plus.dart';

// ---------------- Limits ----------------
const int kMaxUploadBytes = 2 * 1024 * 1024; // 2 MB payload limit
// base64 adds ~33%; keep raw <= ~1.5 MB so base64 stays under 2 MB
const int kRawBudgetForBase64 = ((kMaxUploadBytes * 3) ~/ 4) - 8 * 1024;

// ---------------- API helpers ----------------
String get _apiBaseNormalized {
  var b = ApiConstants.baseUrl.trim();
  if (b.endsWith('/')) b = b.substring(0, b.length - 1);
  if (!b.toLowerCase().endsWith('/api')) b = '$b/api';
  return b;
}

String _resolveFileUrl(String fileNameOrUrl) {
  if (fileNameOrUrl.isEmpty) return fileNameOrUrl;
  final u = fileNameOrUrl.trim();
  if (u.startsWith('http')) return u;
  var base = ApiConstants.baseUrl.trim();
  if (base.endsWith('/')) base = base.substring(0, base.length - 1);
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
          if (val is List && val.isNotEmpty) lines.add("$key: ${val.join(', ')}");
          if (val is String) lines.add("$key: $val");
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
      final v = m['Id'] ?? m['id'] ?? m['CustomerDataId'] ?? m['CustomerId'];
      if (v is int) return v;
      if (v is String) return int.tryParse(v);
    } catch (_) {}
    return null;
  }

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
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
      // IMPORTANT: using GET /api/CustomerDataM/GetAsync/{id}
      final res = await http.get(Uri.parse('$_apiBaseNormalized/CustomerDataM/GetAsync/$id'), headers: headers);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final msg = _extractServerError(res.body) ?? 'HTTP ${res.statusCode}';
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
      } else if (payload['Data'] is Map && (payload['Data']['Documents'] is List)) {
        docs = payload['Data']['Documents'] as List;
      }

      final mapped = <DocumentItem>[];
      for (final e in docs) {
        if (e is Map) {
          final m = Map<String, dynamic>.from(e);
          final idStr = (m['Id'] ?? m['id'] ?? '').toString();
          final remarks = (m['Remarks'] ?? m['remarks'] ?? 'Document').toString();
          final fileName = (m['FileName'] ?? m['fileName'] ?? '').toString();
          final fileType = (m['FileType'] ?? m['fileType'] ?? '').toString();
          final urlRaw = (m['Url'] ?? m['url'] ?? fileName).toString();
          final url = urlRaw.isNotEmpty ? _resolveFileUrl(urlRaw) : null;

          mapped.add(
            DocumentItem(
              id: idStr.isEmpty ? 'srv_${DateTime.now().microsecondsSinceEpoch}' : idStr,
              title: remarks.isEmpty ? 'Document' : remarks,
              localPath: null,
              remoteUrl: url,
              mimeType: fileType.isEmpty ? null : fileType,
            ),
          );
        }
      }
      setState(() {
        _serverDocs
          ..clear()
          ..addAll(mapped);
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
        DocumentItem(id: DateTime.now().microsecondsSinceEpoch.toString(), title: t),
      );
    });
    _typeCtrl.clear();
  }

  // ------------- Pick -> confirm preview -> compress PNG -> upload -------------
  Future<void> _pickAndUpload(DocumentItem d) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'gif', 'bmp', 'tif', 'tiff', 'webp', 'doc', 'docx', 'xls', 'xlsx', 'txt', 'heic'],
    );
    if (result == null || result.files.isEmpty) return;

    final f = result.files.first;
    final name = f.name;
    final ext = p.extension(name).toLowerCase();
    Uint8List? data = f.bytes;
    if (data == null) {
      _snack('Could not read selected file');
      return;
    }

    final isImage = _isImageExt(ext);
    if (isImage) {
      final png = await _compressImageToPngUnderLimit(data);
      if (png == null || png.isEmpty) {
        _snack('Image too large or unsupported. Pick a smaller image.');
        return;
      }
      final confirmed = await _confirmDialog(
        title: 'Upload image?',
        fileName: 'image.png',
        sizeBytes: png.length,
        previewBytes: png,
      );
      if (!confirmed) return;

      await _uploadToServer(
        remarks: d.title,
        bytes: png,
        fileName: 'doc_${DateTime.now().millisecondsSinceEpoch}.png',
        mime: 'image/png',
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
        fileName: name,
        mime: _guessMimeFromExt(ext),
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
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
      final payload = <String, dynamic>{
        "Id": 0,
        "IsModified": true,
        "FileData": base64Encode(bytes),
        "FileName": fileName,
        "FileType": mime,
        "Remarks": remarks,
        "IsDeleted": false,
        "CustomerDataId": cid,
      };

      final url = Uri.parse('$_apiBaseNormalized/CustomerDataM/FileRecordAddAsync');
      final res = await http.post(url, headers: headers, body: jsonEncode(payload));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final msg = _extractServerError(res.body) ?? 'HTTP ${res.statusCode}';
        throw Exception(msg);
      }

      _snack('Uploaded "$remarks"');
      setState(() {
        _pending.removeWhere((x) => x.id == pending.id);
      });
      await _refreshFromServer();
    } catch (e) {
      _snack('Upload failed: $e');
    }
  }

  String _fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

  // ------------- Confirm dialog -------------
  Future<bool> _confirmDialog({
    required String title,
    required String fileName,
    required int sizeBytes,
    Uint8List? previewBytes,
  }) async {
    final sizeStr = _fmtSize(sizeBytes);
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (previewBytes != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(previewBytes, height: 180, fit: BoxFit.cover),
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
                        const Icon(Icons.insert_drive_file_rounded, size: 48, color: Colors.black54),
                        const SizedBox(height: 8),
                        Text(fileName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Text(sizeStr, style: const TextStyle(color: Colors.black54)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: brandBlue, foregroundColor: Colors.white),
                child: const Text('Upload'),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ------------- Open / Download / Share -------------
  Future<String?> _ensureLocalFile(DocumentItem d) async {
    if (d.localPath != null && await File(d.localPath!).exists()) return d.localPath;
    if (d.remoteUrl == null) return null;

    try {
      final token = await TokenStorage.getToken();
      final res = await http.get(Uri.parse(d.remoteUrl!), headers: {
        'Accept': '*/*',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      });
      if (res.statusCode == 200) {
        final dir = await getApplicationDocumentsDirectory();
        final ext = _extFromUrl(d.remoteUrl!);
        final file = File(p.join(dir.path, 'dl_${d.id}_${DateTime.now().millisecondsSinceEpoch}$ext'));
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
    if (d.remoteUrl != null) {
      await Share.share(d.remoteUrl!);
      return;
    }
    final local = await _ensureLocalFile(d);
    if (local != null) {
      await Share.shareXFiles([XFile(local)], text: d.title);
    } else {
      _snack('No file to share');
    }
  }

  Future<void> _download(DocumentItem d) async {
    final local = await _ensureLocalFile(d);
    if (local == null) {
      _snack('Nothing to download yet');
      return;
    }
    final appDir = await getApplicationDocumentsDirectory();
    final downloadsDir = Directory(p.join(appDir.path, 'Downloads'));
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }
    final filename = p.basename(local);
    final dest = p.join(downloadsDir.path, filename);
    await File(local).copy(dest);
    _snack('Saved to ${downloadsDir.path}');
  }

  void _open(DocumentItem d) async {
    final local = await _ensureLocalFile(d);
    if (local == null) return;

    final mime = d.mimeType ?? _guessMimeFromExt(p.extension(local));
    if (mime.startsWith('image/')) {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ImageViewerScreen(path: local, title: d.title)));
    } else if (mime == 'application/pdf' || p.extension(local).toLowerCase() == '.pdf') {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PdfViewerScreen(path: local, title: d.title)));
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
    if (e == '.docx') return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    if (e == '.xls') return 'application/vnd.ms-excel';
    if (e == '.xlsx') return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    if (e == '.txt') return 'text/plain';
    if (e == '.heic') return 'image/heic';
    return 'application/octet-stream';
  }

  bool _isImageExt(String ext) {
    final e = ext.toLowerCase();
    return ['.png', '.jpg', '.jpeg', '.gif', '.bmp', '.tif', '.tiff', '.webp', '.heic'].contains(e);
  }

  Future<Uint8List?> _compressImageToPngUnderLimit(Uint8List input) async {
    try {
      img.Image? decoded = img.decodeImage(input);
      if (decoded == null) return null;

      img.Image working;
      try {
        working = img.bakeOrientation(decoded);
      } catch (_) {
        working = decoded;
      }

      // Pre-limit huge edges for memory usage
      const int maxEdge = 3000;
      if (working.width > maxEdge || working.height > maxEdge) {
        final scale = maxEdge / (working.width > working.height ? working.width : working.height);
        working = img.copyResize(
          working,
          width: (working.width * scale).round(),
          height: (working.height * scale).round(),
          interpolation: img.Interpolation.linear,
        );
      }

      // PNG encode with level increases; then downscale if still too big
      int level = 6;
      Uint8List out = Uint8List.fromList(img.encodePng(working, level: level));
      while (out.length > kRawBudgetForBase64 && level < 9) {
        level++;
        out = Uint8List.fromList(img.encodePng(working, level: level));
      }

      const int minDim = 640;
      while (out.length > kRawBudgetForBase64 && (working.width > minDim && working.height > minDim)) {
        final newW = (working.width * 0.85).round().clamp(1, working.width - 1);
        final newH = (working.height * 0.85).round().clamp(1, working.height - 1);
        working = img.copyResize(
          working,
          width: newW,
          height: newH,
          interpolation: img.Interpolation.linear,
        );
        level = 7;
        out = Uint8List.fromList(img.encodePng(working, level: level));
        while (out.length > kRawBudgetForBase64 && level < 9) {
          level++;
          out = Uint8List.fromList(img.encodePng(working, level: level));
        }
      }

      if (out.length > kRawBudgetForBase64) return null;
      return out;
    } catch (_) {
      return null;
    }
  }

  void _selectForDelete(String id) => setState(() => _selectedId = id);
  void _clearSelection() {
    if (_selectedId != null) setState(() => _selectedId = null);
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ------------- Build -------------
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final padding = width * 0.05;
    final fieldHeight = 50.0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: brandBlue,
        toolbarHeight: 80,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white,
              child: widget.customer.imageBytes != null
                  ? ClipOval(
                      child: Image.memory(
                        widget.customer.imageBytes!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Text(
                      _initials(widget.customer.name),
                      style: TextStyle(color: brandBlue, fontWeight: FontWeight.bold, fontSize: 20),
                    ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(widget.customer.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text(widget.customer.phone, style: const TextStyle(color: Colors.white, fontSize: 14)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _refreshFromServer,
            tooltip: 'Refresh',
          )
        ],
      ),
      body: Column(
        children: [
          // Add Type field
          Container(
            height: fieldHeight,
            margin: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(color: Colors.black12, offset: Offset(1, 1), blurRadius: 2)],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      controller: _typeCtrl,
                      style: const TextStyle(color: Colors.black),
                      decoration: const InputDecoration(
                        hintText: 'Type',
                        hintStyle: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
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
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.only(topRight: Radius.circular(11), bottomRight: Radius.circular(11)),
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
            padding: EdgeInsets.symmetric(horizontal: padding),
            child: Row(
              children: [
                Text('Documents List', style: TextStyle(fontSize: width * 0.045, fontWeight: FontWeight.bold, color: borderColor)),
                if (_loading) ...[
                  const SizedBox(width: 8),
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Colors.black12),

          // List: Pending first, then server docs
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.fromLTRB(padding, 10, padding, padding),
              itemCount: _pending.length + _serverDocs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final isPendingRow = index < _pending.length;
                final d = isPendingRow ? _pending[index] : _serverDocs[index - _pending.length];
                final selected = _selectedId == d.id;

                if (isPendingRow) {
                  // Pending container with Upload
                  return _DocCard(
                    title: d.title,
                    borderColor: borderColor,
                    iconColor: iconColor,
                    selected: selected,
                    preview: null,
                    showUpload: true,
                    onTap: () {
                      if (selected) _clearSelection();
                    },
                    onLongPress: () => _selectForDelete(d.id),
                    onDelete: () {
                      setState(() {
                        _pending.removeWhere((x) => x.id == d.id);
                        _selectedId = null;
                      });
                    },
                    onUpload: () => _pickAndUpload(d),
                    onDownload: null,
                    onShare: null,
                    onOpen: null,
                  );
                } else {
                  // Server document container
                  final isImage = _looksLikeImage(d.mimeType ?? d.remoteUrl ?? '');
                  final preview = isImage && d.remoteUrl != null
                      ? _ServerImagePreview(url: d.remoteUrl!)
                      : null;

                  return _DocCard(
                    title: d.title,
                    borderColor: borderColor,
                    iconColor: iconColor,
                    selected: selected,
                    preview: preview,
                    showUpload: false,
                    onTap: () {
                      if (selected) {
                        _clearSelection();
                      } else {
                        _open(d);
                      }
                    },
                    onLongPress: () => _selectForDelete(d.id), // not deleting from server in this build
                    onDelete: null,
                    onUpload: null,
                    onDownload: () => _download(d),
                    onShare: () => _share(d),
                    onOpen: () => _open(d),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _looksLikeImage(String s) {
    final lower = s.toLowerCase();
    if (lower.startsWith('image/')) return true;
    final ext = p.extension(lower);
    return ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.tif', '.tiff', '.heic'].contains(ext);
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
    this.preview,
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
    final textColor = selected ? Colors.white : Colors.black87;
    final border = selected ? Colors.red : borderColor;

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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row
              Row(
                children: [
                  Expanded(
                    child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textColor)),
                  ),
                  Row(
                    children: [
                      if (showUpload && onUpload != null)
                        IconButton(
                          onPressed: onUpload,
                          icon: Icon(Icons.upload_rounded, color: iconColor, size: 24),
                          tooltip: 'Upload',
                        ),
                      if (onOpen != null)
                        IconButton(
                          onPressed: onOpen,
                          icon: Icon(Icons.visibility_rounded, color: iconColor, size: 22),
                          tooltip: 'Open',
                        ),
                      if (onDownload != null)
                        IconButton(
                          onPressed: onDownload,
                          icon: Icon(Icons.download_rounded, color: iconColor, size: 24),
                          tooltip: 'Download',
                        ),
                      if (onShare != null)
                        IconButton(
                          onPressed: onShare,
                          icon: Icon(Icons.share, color: iconColor, size: 22),
                          tooltip: 'Share',
                        ),
                      if (selected && onDelete != null)
                        IconButton(
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete, color: Colors.white, size: 24),
                          tooltip: 'Delete',
                        ),
                    ],
                  ),
                ],
              ),
              // Inline preview for images
              if (preview != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(height: 160, width: double.infinity, child: preview),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ServerImagePreview extends StatefulWidget {
  const _ServerImagePreview({required this.url});
  final String url;

  @override
  State<_ServerImagePreview> createState() => _ServerImagePreviewState();
}

class _ServerImagePreviewState extends State<_ServerImagePreview> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final token = await TokenStorage.getToken();
      final res = await http.get(Uri.parse(widget.url), headers: {
        'Accept': '*/*',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      });
      if (mounted) {
        setState(() {
          _bytes = (res.statusCode >= 200 && res.statusCode < 300) ? res.bodyBytes : null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_bytes == null || _bytes!.isEmpty) {
      return Container(
        color: Colors.grey.shade100,
        alignment: Alignment.center,
        child: const Text('Preview not available', style: TextStyle(color: Colors.black54)),
      );
    }
    return Image.memory(_bytes!, fit: BoxFit.cover);
  }
}

// ---------------- Viewers ----------------
class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({super.key, required this.path, required this.title});
  final String path;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), backgroundColor: const Color(0xFF38B6E4)),
      body: PhotoView(
        backgroundDecoration: const BoxDecoration(color: Colors.white),
        imageProvider: FileImage(File(path)),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 2.5,
      ),
    );
  }
}

class PdfViewerScreen extends StatefulWidget {
  const PdfViewerScreen({super.key, required this.path, required this.title});
  final String path;
  final String title;

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late PdfControllerPinch controller;

  @override
  void initState() {
    super.initState();
    controller = PdfControllerPinch(document: PdfDocument.openFile(widget.path));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), backgroundColor: const Color(0xFF38B6E4)),
      body: PdfViewPinch(controller: controller),
    );
  }
}