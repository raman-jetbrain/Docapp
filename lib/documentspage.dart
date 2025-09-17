import 'dart:convert';
import 'dart:io';
import 'package:docapp/model/DocumentsItem.dart';
import 'package:docapp/model/customermodel.dart' as model;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';


class DocumentsPage extends StatefulWidget {
  final model.Customer customer;

  const DocumentsPage({super.key, required this.customer});

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  final TextEditingController _typeCtrl = TextEditingController();
  final List<DocumentItem> _docs = [];
  String? _selectedId;

  Color get brandBlue => const Color(0xFF38B6E4);
  Color get borderColor => Colors.black;
  Color get iconColor => Colors.black;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  @override
  void dispose() {
    _typeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'docs_${widget.customer.phone}'; // Use phone as unique key
    final docsJson = prefs.getString(key);
    if (docsJson != null) {
      final List<dynamic> docsList = json.decode(docsJson);
      setState(() {
        _docs.clear();
        _docs.addAll(docsList.map((e) => DocumentItem.fromMap(Map<String, dynamic>.from(e))));
      });
    }
  }

  Future<void> _saveDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'docs_${widget.customer.phone}';
    final docsMapList = _docs.map((d) => d.toMap()).toList();
    await prefs.setString(key, json.encode(docsMapList));
  }

  Future<void> _addType() async {
    final t = _typeCtrl.text.trim();
    if (t.isEmpty) {
      _snack('Please enter a type name');
      return;
    }
    setState(() {
      _docs.insert(
        0,
        DocumentItem(id: DateTime.now().microsecondsSinceEpoch.toString(), title: t),
      );
    });
    _typeCtrl.clear();
    await _saveDocuments();
  }

  Future<void> _pickAndAttach(DocumentItem d) async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withReadStream: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final dir = await getApplicationDocumentsDirectory();
    final ext = p.extension(f.name);
    final target = File(p.join(dir.path, 'docs_${d.id}_${DateTime.now().millisecondsSinceEpoch}$ext'));

    if (f.readStream != null) {
      final sink = target.openWrite();
      await f.readStream!.pipe(sink);
      await sink.flush();
      await sink.close();
    } else if (f.path != null) {
      await File(f.path!).copy(target.path);
    } else {
      _snack('Could not read selected file');
      return;
    }

    setState(() {
      d.localPath = target.path;
      d.mimeType = _guessMimeFromExt(ext);
    });
    await _saveDocuments();
    _snack('File attached to ${d.title}');
  }

  Future<void> _share(DocumentItem d) async {
    final local = await _ensureLocalFile(d);
    if (local == null) {
      if (d.remoteUrl != null) {
        await Share.share(d.remoteUrl!);
      } else {
        _snack('No file to share');
      }
      return;
    }
    await Share.shareXFiles([XFile(local)], text: d.title);
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

  Future<String?> _ensureLocalFile(DocumentItem d) async {
    if (d.localPath != null && await File(d.localPath!).exists()) return d.localPath;
    if (d.remoteUrl == null) return null;

    try {
      final res = await http.get(Uri.parse(d.remoteUrl!));
      if (res.statusCode == 200) {
        final dir = await getApplicationDocumentsDirectory();
        final ext = _extFromUrl(d.remoteUrl!);
        final file = File(p.join(dir.path, 'dl_${d.id}_${DateTime.now().millisecondsSinceEpoch}$ext'));
        await file.writeAsBytes(res.bodyBytes);
        d.localPath = file.path;
        d.mimeType ??= _guessMimeFromExt(ext);
        await _saveDocuments();
        return d.localPath;
      }
    } catch (_) {}
    return null;
  }

  void _open(DocumentItem d) async {
    final local = await _ensureLocalFile(d);
    if (local == null) {
      _snack('Please upload or set a remote URL first');
      return;
    }
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

  void _selectForDelete(String id) {
    setState(() => _selectedId = id);
  }

  void _clearSelection() {
    if (_selectedId != null) {
      setState(() => _selectedId = null);
    }
  }

  Future<void> _confirmDelete(DocumentItem d) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('Are you sure delete?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OK', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      setState(() {
        _docs.removeWhere((x) => x.id == d.id);
        _selectedId = null;
      });
      await _saveDocuments();
      _snack('Deleted');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  static String _extFromUrl(String url) {
    final u = Uri.parse(url);
    final path = u.path;
    final ext = p.extension(path);
    return ext.isEmpty ? '' : ext;
  }

  static String _guessMimeFromExt(String ext) {
    final e = ext.toLowerCase();
    if (e == '.jpg' || e == '.jpeg') return 'image/jpeg';
    if (e == '.png') return 'image/png';
    if (e == '.gif') return 'image/gif';
    if (e == '.pdf') return 'application/pdf';
    if (e == '.heic') return 'image/heic';
    return 'application/octet-stream';
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final padding = width * 0.05;
    final fieldHeight = 50.0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: brandBlue,
        toolbarHeight: 80, // increased height
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
                      style: TextStyle(
                        color: brandBlue,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.customer.name,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  widget.customer.phone,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Fixed Add Type field at top
          Container(
            height: fieldHeight,
            margin: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Colors.black12, offset: Offset(1, 1), blurRadius: 2),
              ],
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

          // Documents list header
          Padding(
            padding: EdgeInsets.symmetric(horizontal: padding),
            child: Row(
              children: [
                Text(
                  'Documents List',
                  style: TextStyle(fontSize: width * 0.045, fontWeight: FontWeight.bold, color: borderColor),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Colors.black12),

          // Documents list scrolls under system nav bar properly
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.fromLTRB(padding, 10, padding, padding),
              itemCount: _docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final d = _docs[index];
                final selected = _selectedId == d.id;
                return _DocCard(
                  title: d.title,
                  borderColor: borderColor,
                  iconColor: iconColor,
                  selected: selected,
                  onTap: () {
                    if (selected) {
                      _clearSelection();
                    } else {
                      _open(d);
                    }
                  },
                  onLongPress: () => _selectForDelete(d.id),
                  onDelete: () => _confirmDelete(d),
                  onUpload: () => _pickAndAttach(d),
                  onDownload: d.localPath != null ? () => _download(d) : null,
                  onShare: () => _share(d),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DocCard extends StatelessWidget {
  const _DocCard({
    required this.title,
    required this.onTap,
    required this.onUpload,
    required this.onDownload,
    required this.onShare,
    required this.borderColor,
    required this.iconColor,
    required this.selected,
    this.onLongPress,
    this.onDelete,
  });

  final String title;
  final VoidCallback onTap;
  final VoidCallback onUpload;
  final VoidCallback? onDownload;
  final VoidCallback onShare;
  final VoidCallback? onLongPress;
  final VoidCallback? onDelete;
  final Color borderColor;
  final Color iconColor;
  final bool selected;

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
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textColor),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: onUpload,
                    icon: Icon(Icons.upload_rounded, color: iconColor, size: 24),
                    tooltip: 'Upload',
                  ),
                  if (onDownload != null)
                    IconButton(
                      onPressed: onDownload,
                      icon: Icon(Icons.download_rounded, color: iconColor, size: 24),
                      tooltip: 'Download',
                    ),
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
              )
            ],
          ),
        ),
      ),
    );
  }
}

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