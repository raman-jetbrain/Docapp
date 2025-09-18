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
import 'package:photo_view/photo_view.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kPrimaryBlue = Color(0xFF3B5998);

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

  // ---------------- Data Load/Save ----------------
  Future<void> _loadDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'docs_${widget.customer.phone}';
    final docsJson = prefs.getString(key);
    if (docsJson != null) {
      final docsList = json.decode(docsJson) as List;
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

  // ---------------- Actions ----------------
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
    final target = File(
        p.join(dir.path, 'docs_${d.id}_${DateTime.now().millisecondsSinceEpoch}$ext'));

    if (f.readStream != null) {
      final sink = target.openWrite();
      await f.readStream!.pipe(sink);
      await sink.close();
    } else if (f.path != null) {
      await File(f.path!).copy(target.path);
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
    if (local != null) {
      await Share.shareXFiles([XFile(local)], text: d.title);
    } else if (d.remoteUrl != null) {
      await Share.share(d.remoteUrl!);
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
    final dest = p.join(downloadsDir.path, p.basename(local));
    await File(local).copy(dest);
    _snack('Saved to $dest');
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
      _snack('Upload or set a remote URL first');
      return;
    }
    final mime = d.mimeType ?? _guessMimeFromExt(p.extension(local));
    if (mime.startsWith('image/')) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ImageViewerScreen(path: local, title: d.title)),
      );
    } else if (mime == 'application/pdf') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PdfViewerScreen(path: local, title: d.title)),
      );
    } else {
      await OpenFilex.open(local);
    }
  }

  Future<void> _confirmDelete(DocumentItem d) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      setState(() => _docs.removeWhere((x) => x.id == d.id));
      await _saveDocuments();
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  static String _extFromUrl(String url) => p.extension(Uri.parse(url).path);
  static String _guessMimeFromExt(String ext) {
    switch (ext.toLowerCase()) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.pdf':
        return 'application/pdf';
      case '.heic':
        return 'image/heic';
    }
    return 'application/octet-stream';
  }

  String _initials(String name) {
    final parts = name.split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return parts.first[0].toUpperCase() + parts.last[0].toUpperCase();
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final padding = width * 0.05;

    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.white,

      // 🔹 AppBar with background image + logo (like Dashboard)
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(120),
        child: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage("assets/images/Background2.jpeg"),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          "assets/images/logo2.png",
                          height: 60,
                          width: 90,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(widget.customer.name,
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                            Text(widget.customer.phone,
                                style: const TextStyle(color: Colors.white70, fontSize: 14)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),

      body: Column(
        children: [
          Container(
            margin: EdgeInsets.all(padding),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _typeCtrl,
                    decoration: const InputDecoration(
                        hintText: 'Document Type',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(10)),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: kPrimaryBlue),
                  onPressed: _addType,
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: _docs.isEmpty
                ? const Center(child: Text("No documents added"))
                : ListView.builder(
                    itemCount: _docs.length,
                    itemBuilder: (context, index) {
                      final d = _docs[index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.folder, color: kPrimaryBlue),
                          title: Text(d.title),
                          onTap: () => _open(d),
                          trailing: Wrap(spacing: 4, children: [
                            IconButton(icon: const Icon(Icons.upload), onPressed: () => _pickAndAttach(d)),
                            if (d.localPath != null)
                              IconButton(icon: const Icon(Icons.download), onPressed: () => _download(d)),
                            IconButton(icon: const Icon(Icons.share), onPressed: () => _share(d)),
                            IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _confirmDelete(d)),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),

      // 🔹 Floating Bottom NavBar
      bottomNavigationBar: Container(
        margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
        height: 65,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 8))
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(Icons.home, "Home", false),
            _navItem(Icons.group, "Customers", false),
            _navItem(Icons.add_circle, "Add", false),
            _navItem(Icons.event, "Events", false),
            _navItem(Icons.folder, "Documents", true),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, bool selected) {
    return InkWell(
      onTap: () {}, // TODO: add navigation
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: selected ? kPrimaryBlue : Colors.grey),
          Text(label, style: TextStyle(color: selected ? kPrimaryBlue : Colors.grey)),
        ],
      ),
    );
  }
}

// ---------------- Viewers ----------------
class ImageViewerScreen extends StatelessWidget {
  final String path, title;
  const ImageViewerScreen({super.key, required this.path, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), backgroundColor: kPrimaryBlue),
      body: PhotoView(imageProvider: FileImage(File(path))),
    );
  }
}

class PdfViewerScreen extends StatefulWidget {
  final String path, title;
  const PdfViewerScreen({super.key, required this.path, required this.title});
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
      appBar: AppBar(backgroundColor: kPrimaryBlue, title: Text(widget.title)),
      body: PdfViewPinch(controller: controller),
    );
  }
}