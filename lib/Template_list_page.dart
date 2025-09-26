// main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';

class TemplateSummary {
  final String id;
  final String title;
  final String thumbnail;

  TemplateSummary({
    required this.id,
    required this.title,
    required this.thumbnail,
  });

  factory TemplateSummary.fromJson(Map<String, dynamic> j) => TemplateSummary(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? j['name'] ?? '').toString(),
        thumbnail: (j['thumbnail'] ?? j['thumb'] ?? j['preview'] ?? '').toString(),
      );
}

class TemplateApi {
  static const bool useFakeApi = true; // toggle

  static const String baseUrl = ''; // real API here
  static const String apiKey = 'c5c6...'; // your API token
  static const AuthHeaderType authHeaderType = AuthHeaderType.basic;

  static Map<String, String> _headers({bool jsonBody = false}) {
    final h = <String, String>{'Accept': 'application/json'};
    if (jsonBody) h['Content-Type'] = 'application/json';

    switch (authHeaderType) {
      case AuthHeaderType.basic:
        h['Authorization'] = 'Basic $apiKey';
        break;
      case AuthHeaderType.bearer:
        h['Authorization'] = 'Bearer $apiKey';
        break;
      case AuthHeaderType.xApiKey:
        h['x-api-key'] = apiKey;
        break;
    }
    return h;
  }

  static void _throwIfFailed(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  /* ------------------------------
    Public wrapper methods
  ------------------------------ */
  static Future<List<TemplateSummary>> getTemplates() =>
      useFakeApi ? _getTemplatesFake() : _getTemplatesReal();

  static Future<Map<String, dynamic>> getTemplateDetails(String id) =>
      useFakeApi ? _getTemplateDetailsFake(id) : _getTemplateDetailsReal(id);

  /* ------------------------------
    Real API (replace with yours)
  ------------------------------ */
  static Future<List<TemplateSummary>> _getTemplatesReal() async {
    final uri = Uri.parse('$baseUrl/templates');
    final res = await http.get(uri, headers: _headers());
    _throwIfFailed(res);

    final decoded = jsonDecode(res.body);
    final List list = decoded is List
        ? decoded
        : (decoded is Map && decoded['data'] is List)
            ? decoded['data']
            : [];

    return list
        .map((e) => TemplateSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<Map<String, dynamic>> _getTemplateDetailsReal(String id) async {
    final uri = Uri.parse('$baseUrl/templates/$id');
    final res = await http.get(uri, headers: _headers());
    _throwIfFailed(res);

    final decoded = jsonDecode(res.body);

    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
      return Map<String, dynamic>.from(decoded.first);
    }
    throw Exception('Unexpected response format');
  }

  /* ------------------------------
    Fake API (local dev)
  ------------------------------ */
  static Future<List<TemplateSummary>> _getTemplatesFake() async {
    await Future.delayed(const Duration(milliseconds: 400));
    final data = [
      {
        "id": "t1",
        "title": "Birthday – Gold & Balloons",
        "thumbnail": "https://picsum.photos/seed/bday1/600/800"
      },
      {
        "id": "t2",
        "title": "Neon Celebration",
        "thumbnail": "https://picsum.photos/seed/bday2/600/800"
      },
      {
        "id": "t3",
        "title": "Minimal Pastel",
        "thumbnail": "https://picsum.photos/seed/bday3/600/800"
      },
    ];
    return data.map((e) => TemplateSummary.fromJson(e)).toList();
  }

  static Future<Map<String, dynamic>> _getTemplateDetailsFake(
      String id) async {
    await Future.delayed(const Duration(milliseconds: 400));


    if (id == 't2') {
      return {
        "background": "#0F1020",
        "elements": [
          {
            "type": "image",
            "src": "https://picsum.photos/seed/confetti/600/400",
            "x": 10,
            "y": 10,
            "width": 300,
            "height": 220
          },
          {
            "type": "text",
            "content": "HAPPY BIRTHDAY",
            "x": 32,
            "y": 250,
            "fontSize": 28,
            "color": "#00E5FF",
            "weight": "bold"
          },
          {
            "type": "text",
            "content": "{{name}}",
            "x": 40,
            "y": 292,
            "fontSize": 26,
            "color": "#FFFFFF",
            "placeholder": "Enter Name"
          },
        ]
      };
    } else if (id == 't3') {
      return {
        "background": "#F9F5FF",
        "elements": [
          {
            "type": "text",
            "content": "Happy Birthday,",
            "x": 24,
            "y": 36,
            "fontSize": 24,
            "color": "#6D28D9"
          },
          {
            "type": "text",
            "content": "{{name}}",
            "x": 24,
            "y": 70,
            "fontSize": 30,
            "color": "#111827",
            "weight": "700",
            "placeholder": "Enter Name"
          },
          {
            "type": "image",
            "src": "https://picsum.photos/seed/baloons/400/300",
            "x": 70,
            "y": 140,
            "width": 180,
            "height": 180
          }
        ]
      };
    }


    return {
      "background": "#101827",
      "elements": [
        {
          "type": "image",
          "src": "https://picsum.photos/seed/balloons/800/600",
          "x": 0,
          "y": 0,
          "width": 320,
          "height": 200
        },
        {
          "type": "text",
          "content": "🎉 Happy Birthday 🎉",
          "x": 30,
          "y": 220,
          "fontSize": 26,
          "color": "#FFD700",
          "weight": "bold"
        },
        {
          "type": "text",
          "content": "{{name}}",
          "x": 30,
          "y": 260,
          "fontSize": 28,
          "color": "#FFFFFF",
          "placeholder": "Enter Name"
        },
      ]
    };

  }
}

enum AuthHeaderType { basic, bearer, xApiKey }


class TemplateListScreen extends StatefulWidget {
  final Map<String, dynamic> customer; // optional

  const TemplateListScreen({super.key, required this.customer });

  @override
  State<TemplateListScreen> createState() => _TemplateListScreenState();
}

class _TemplateListScreenState extends State<TemplateListScreen> {
  late Future<List<TemplateSummary>> _templates;

  @override
  void initState() {
    super.initState();
    _templates = TemplateApi.getTemplates();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: const Text("Choose Template"), backgroundColor: Colors.blue),
      body: FutureBuilder<List<TemplateSummary>>(
        future: _templates,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final data = snap.data ?? [];
          if (data.isEmpty) {
            return const Center(child: Text("No templates available"));
          }
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12),
            itemCount: data.length,
            itemBuilder: (context, i) {
              final template = data[i];
              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          PosterEditorScreen(templateId: template.id)),
                ),
                child: Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius:
                              const BorderRadius.vertical(top: Radius.circular(12)),
                          child: Image.network(template.thumbnail, fit: BoxFit.cover),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(template.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                      )
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}


class PosterEditorScreen extends StatefulWidget {
  final String templateId;
  const PosterEditorScreen({super.key, required this.templateId});

  @override
  State<PosterEditorScreen> createState() => _PosterEditorScreenState();
}

class _PosterEditorScreenState extends State<PosterEditorScreen> {
  final _posterKey = GlobalKey();
  late Future<Map<String, dynamic>> _templateDetails;
  Map<String, String> _fields = {};
  File? _uploadedImage;
  final picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _templateDetails = TemplateApi.getTemplateDetails(widget.templateId);
    _templateDetails.then((d) {
      setState(() {
        _fields = _extractPlaceholders(d);
      });
    });
  }

  Map<String, String> _extractPlaceholders(Map<String, dynamic> d) {
    final out = <String, String>{};
    for (final e in (d['elements'] as List)) {
      if (e['type'] == 'text') {
        final c = e['content'] as String;
        if (c.contains('{{')) {
          final key = c.replaceAll(RegExp(r'[{}]'), '');
          out[key] = e['placeholder'] ?? key;
        }
      }
    }
    return out;
  }

  Future<void> _pickImg() async {
    final x = await picker.pickImage(source: ImageSource.gallery);
    if (x != null) {
      setState(() {
        _uploadedImage = File(x.path);
      });
    }
  }

  String _populate(String c) {
    var res = c;
    _fields.forEach((k, v) {
      res = res.replaceAll('{{$k}}', v);
    });
    return res;
  }

  Future<void> _share() async {
    RenderRepaintBoundary bound =
        _posterKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final ui.Image im = await bound.toImage(pixelRatio: 3);
    final byteData = await im.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    final dir = await getTemporaryDirectory();
    final f = await File('${dir.path}/poster.png').create();
    await f.writeAsBytes(pngBytes);
    await Share.shareXFiles([XFile(f.path)], text: "Check this poster!");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Poster"),
        actions: [IconButton(onPressed: _share, icon: const Icon(Icons.share))],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _templateDetails,
        builder: (c, snap) {
          if (!snap.hasData) {
            if (snap.hasError) {
              return Center(child: Text('Error: ${snap.error}'));
            }
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!;
          final elements = data['elements'] as List;
          final bg = data['background'] ?? "#FFFFFF";
          final bgColor = Color(int.parse(bg.substring(1), radix: 16)).withOpacity(1);

          return Column(children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: RepaintBoundary(
                    key: _posterKey,
                    child: Container(
                      color: bgColor,
                      child: Stack(
                        children: [
                          for (var e in elements)
                            if (e['type'] == 'image')
                              Positioned(
                                  left: (e['x'] as num).toDouble(),
                                  top: (e['y'] as num).toDouble(),
                                  width: (e['width'] as num).toDouble(),
                                  height: (e['height'] as num).toDouble(),
                                  child: Image.network(e['src'], fit: BoxFit.cover)),
                          for (var e in elements)
                            if (e['type'] == 'text')
                              Positioned(
                                left: (e['x'] as num).toDouble(),
                                top: (e['y'] as num).toDouble(),
                                child: Text(
                                  _populate(e['content']),
                                  style: TextStyle(
                                    color: Color(
                                        int.parse(e['color'].substring(1), radix: 16)),
                                    fontSize: (e['fontSize'] as num).toDouble(),
                                    fontWeight: e['weight'] == 'bold'
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                          if (_uploadedImage != null)
                            Positioned.fill(
                                child:
                                    Image.file(_uploadedImage!, fit: BoxFit.cover)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ..._fields.keys.map((k) {
              return Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  decoration: InputDecoration(
                      labelText: _fields[k], border: const OutlineInputBorder()),
                  onChanged: (v) {
                    setState(() {
                      _fields[k] = v;
                    });
                  },
                ),
              );
            }),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _pickImg,
              icon: const Icon(Icons.photo),
              label: const Text("Upload Photo"),
            ),
            const SizedBox(height: 20),
          ]);
        },
      ),
    );
  }
}