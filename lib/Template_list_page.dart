// main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';

// Your Template API and models
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
  // Toggle this to false to use your real API
  static const bool useFakeApi = true;

  // 1) Set your base URL here (example)
  static const String baseUrl = '';

  // 2) Your API key
  static const String apiKey = 'c5c6MzgzNjc6MzU1NjI6OWpCQm93TmVPUUZnWWlGWA=';

  // 3) Choose how the API expects the key.
  static const AuthHeaderType authHeaderType = AuthHeaderType.basic;

  static Map<String, String> _headers({bool jsonBody = false}) {
    final h = <String, String>{
      'Accept': 'application/json',
    };
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

  // Public methods used by your app
  static Future<List<TemplateSummary>> getTemplates() =>
      useFakeApi ? _getTemplatesFake() : _getTemplatesReal();

  static Future<Map<String, dynamic>> getTemplateDetails(String id) =>
      useFakeApi ? _getTemplateDetailsFake(id) : _getTemplateDetailsReal(id);

  /* ---------------- Real API calls ---------------- */

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
    throw Exception('Unexpected response format for template details');
  }

  /* ---------------- Fake API (for local dev) ---------------- */

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

  static Future<Map<String, dynamic>> _getTemplateDetailsFake(String id) async {
    await Future.delayed(const Duration(milliseconds: 400));

    if (id == 't2') {
      return {
        "background": "#0F1020",
        "elements": [
          {
            "type": "image",
            "src": "https://picsum.photos/seed/confetti/600/400",
            "x": 10, "y": 10, "width": 300, "height": 220
          },
          {
            "type": "text",
            "content": "HAPPY BIRTHDAY",
            "x": 32, "y": 250, "fontSize": 28, "color": "#00E5FF", "weight": "bold"
          },
          {
            "type": "text",
            "content": "{{name}}",
            "x": 40, "y": 292, "fontSize": 26, "color": "#FFFFFF", "placeholder": "Enter Name"
          },
          {
            "type": "text",
            "content": "Contact: {{phone}}",
            "x": 40, "y": 330, "fontSize": 16, "color": "#F8F8F8", "placeholder": "Enter Phone"
          }
        ]
      };
    } else if (id == 't3') {
      return {
        "background": "#F9F5FF",
        "elements": [
          {
            "type": "text",
            "content": "Happy Birthday,",
            "x": 24, "y": 36, "fontSize": 24, "color": "#6D28D9"
          },
          {
            "type": "text",
            "content": "{{name}}",
            "x": 24, "y": 70, "fontSize": 30, "color": "#111827", "weight": "700", "placeholder": "Enter Name"
          },
          {
            "type": "image",
            "src": "https://picsum.photos/seed/baloons/400/300",
            "x": 70, "y": 140, "width": 180, "height": 180
          },
          {
            "type": "text",
            "content": "Call: {{phone}}",
            "x": 24, "y": 380, "fontSize": 16, "color": "#374151", "placeholder": "Enter Phone"
          }
        ]
      };
    }

    // Default (t1)
    return {
      "background": "#101827",
      "elements": [
        {
          "type": "image",
          "src": "https://picsum.photos/seed/balloons/800/600",
          "x": 0, "y": 0, "width": 320, "height": 200
        },
        {
          "type": "text",
          "content": "🎉 Happy Birthday 🎉",
          "x": 30, "y": 220, "fontSize": 26, "color": "#FFD700", "weight": "bold"
        },
        {
          "type": "text",
          "content": "{{name}}",
          "x": 30, "y": 260, "fontSize": 28, "color": "#FFFFFF", "placeholder": "Enter Name"
        },
        {
          "type": "text",
          "content": "Contact: {{phone}}",
          "x": 30, "y": 300, "fontSize": 16, "color": "#E5E7EB", "placeholder": "Enter Phone"
        }
      ]
    };
  }

  static void _throwIfFailed(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }
}

enum AuthHeaderType { basic, bearer, xApiKey }

// Main App
void main() => runApp(const PosterApp());

class PosterApp extends StatelessWidget {
  const PosterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dynamic Poster App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const TemplateListScreen(),
    );
  }
}

// Template List Screen
class TemplateListScreen extends StatefulWidget {
  const TemplateListScreen({super.key});

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
      appBar: AppBar(
        title: const Text('Choose a Template'),
      ),
      body: FutureBuilder<List<TemplateSummary>>(
        future: _templates,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No templates found.'));
          } else {
            return GridView.builder(
              padding: const EdgeInsets.all(16.0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16.0,
                mainAxisSpacing: 16.0,
                childAspectRatio: 0.7,
              ),
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                final template = snapshot.data![index];
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PosterEditorScreen(templateId: template.id),
                      ),
                    );
                  },
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                            child: Image.network(
                              template.thumbnail,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            template.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          }
        },
      ),
    );
  }
}

// Poster Editor Screen
class PosterEditorScreen extends StatefulWidget {
  final String templateId;

  const PosterEditorScreen({super.key, required this.templateId});

  @override
  State<PosterEditorScreen> createState() => _PosterEditorScreenState();
}

class _PosterEditorScreenState extends State<PosterEditorScreen> {
  final _posterKey = GlobalKey();
  late Future<Map<String, dynamic>> _templateDetails;
  Map<String, String> _editableFields = {};
  File? _uploadedImage;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _templateDetails = TemplateApi.getTemplateDetails(widget.templateId);
    _templateDetails.then((data) {
      if (mounted) {
        setState(() {
          _editableFields = _extractPlaceholders(data);
        });
      }
    });
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _uploadedImage = File(image.path);
      });
    }
  }

  Map<String, String> _extractPlaceholders(Map<String, dynamic> data) {
    final Map<String, String> placeholders = {};
    final elements = data['elements'] as List<dynamic>?;
    if (elements == null) return placeholders;

    for (final element in elements) {
      if (element['type'] == 'text') {
        final content = element['content'] as String;
        if (content.contains('{{') && content.contains('}}')) {
          final placeholderName = content.replaceAll(RegExp(r'[{}]'), '');
          placeholders[placeholderName] = element['placeholder'] ?? placeholderName;
        }
      }
    }
    return placeholders;
  }

  String _populateContent(String content, Map<String, String> fields) {
    String result = content;
    fields.forEach((key, value) {
      result = result.replaceAll('{{$key}}', value.isEmpty ? '{{$key}}' : value);
    });
    return result;
  }

  Future<void> _sharePoster() async {
    try {
      RenderRepaintBoundary boundary =
          _posterKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/poster.png').create();
      await file.writeAsBytes(pngBytes);

      await Share.shareXFiles([XFile(file.path)], text: 'Check out this poster!');
    } catch (e) {
      print('Error sharing poster: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit and Share'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _sharePoster,
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _templateDetails,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData) {
            return const Center(child: Text('Template not found.'));
          } else {
            final templateData = snapshot.data!;
            final elements = templateData['elements'] as List<dynamic>;
            final backgroundColor = Color(int.parse(templateData['background'].substring(1), radix: 16));

            return Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 3 / 4, // Poster aspect ratio
                      child: RepaintBoundary(
                        key: _posterKey,
                        child: Container(
                          color: backgroundColor,
                          child: Stack(
                            children: [
                              ...elements.map((e) {
                                if (e['type'] == 'image') {
                                  return Positioned(
                                    left: (e['x'] as num).toDouble(),
                                    top: (e['y'] as num).toDouble(),
                                    width: (e['width'] as num).toDouble(),
                                    height: (e['height'] as num).toDouble(),
                                    child: Image.network(
                                      e['src'],
                                      fit: BoxFit.cover,
                                    ),
                                  );
                                }
                                if (e['type'] == 'text') {
                                  final content = _populateContent(e['content'], _editableFields);
                                  return Positioned(
                                    left: (e['x'] as num).toDouble(),
                                    top: (e['y'] as num).toDouble(),
                                    child: Text(
                                      content,
                                      style: TextStyle(
                                        color: Color(int.parse(e['color'].substring(1), radix: 16)),
                                        fontSize: (e['fontSize'] as num).toDouble(),
                                        fontWeight: e['weight'] == 'bold' || e['weight'] == '700'
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              }),
                              // UPLOAD CONTAINER
                              Positioned.fill(
                                child: _uploadedImage != null
                                  ? Image.file(_uploadedImage!, fit: BoxFit.cover)
                                  : Center(
                                      child: GestureDetector(
                                        onTap: _pickImage,
                                        child: Container(
                                          width: 150,
                                          height: 150,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.2),
                                            border: Border.all(color: Colors.white, width: 2, style: BorderStyle.none),
                                          ),
                                          child: const Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.add_photo_alternate, size: 50, color: Colors.white),
                                              Text('Upload Photo', style: TextStyle(color: Colors.white)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: _editableFields.keys.map((key) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: TextField(
                          onChanged: (value) {
                            setState(() {
                              _editableFields[key] = value;
                            });
                          },
                          decoration: InputDecoration(
                            labelText: _editableFields[key]!,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            );
          }
        },
      ),
    );
  }
}