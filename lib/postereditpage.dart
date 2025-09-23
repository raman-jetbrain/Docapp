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

// Custom data model for our editable elements
class ElementData {
  String id;
  String type;
  double x, y, width, height, rotation;
  Color? color;
  String? content;
  String? src;
  double? fontSize;
  FontWeight? fontWeight;
  String? placeholder;

  ElementData({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0.0,
    this.color,
    this.content,
    this.src,
    this.fontSize,
    this.fontWeight,
    this.placeholder,
  });

  factory ElementData.fromJson(Map<String, dynamic> j) {
    String id = DateTime.now().microsecondsSinceEpoch.toString();
    double x = (j['x'] as num?)?.toDouble() ?? 0;
    double y = (j['y'] as num?)?.toDouble() ?? 0;
    double width = (j['width'] as num?)?.toDouble() ?? 100;
    double height = (j['height'] as num?)?.toDouble() ?? 100;
    Color? color;
    if (j['color'] != null) {
      color = Color(int.parse(j['color'].substring(1), radix: 16));
    }
    FontWeight fontWeight = FontWeight.normal;
    if (j['weight'] == 'bold' || j['weight'] == '700') {
      fontWeight = FontWeight.bold;
    }
    double? fontSize = (j['fontSize'] as num?)?.toDouble();

    return ElementData(
      id: id,
      type: j['type'],
      x: x,
      y: y,
      width: width,
      height: height,
      color: color,
      content: j['content'],
      src: j['src'],
      fontSize: fontSize,
      fontWeight: fontWeight,
      placeholder: j['placeholder'],
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
  List<ElementData> _elements = [];
  Color _backgroundColor = Colors.white;
  ElementData? _selectedElement;
  final double _posterAspectRatio = 3 / 4;

  @override
  void initState() {
    super.initState();
    _templateDetails = TemplateApi.getTemplateDetails(widget.templateId);
    _templateDetails.then((data) {
      if (mounted) {
        setState(() {
          _backgroundColor = Color(int.parse(data['background'].substring(1), radix: 16));
          _elements = (data['elements'] as List)
              .map((e) => ElementData.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          _editableFields = _extractPlaceholders(data);
        });
      }
    });
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

  void _selectElement(ElementData? element) {
    setState(() {
      _selectedElement = element;
    });
  }

  void _onPanUpdate(ElementData element, DragUpdateDetails details) {
    setState(() {
      element.x += details.delta.dx;
      element.y += details.delta.dy;
    });
  }

  void _onScaleUpdate(ElementData element, ScaleUpdateDetails details) {
    setState(() {
      element.width = (element.width * details.scale).clamp(10.0, 500.0);
      element.height = (element.height * details.scale).clamp(10.0, 500.0);
    });
  }

  void _changeBackgroundColor() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Change Background Color'),
          content: SingleChildScrollView(
            child: Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: [
                Colors.red, Colors.blue, Colors.green, Colors.yellow, Colors.purple,
                Colors.orange, Colors.pink, Colors.brown, Colors.black, Colors.white,
              ].map((color) {
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _backgroundColor = color;
                    });
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  void _editElement(ElementData element) {
    if (element.type == 'text') {
      TextEditingController controller = TextEditingController(text: element.content);
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Edit Text'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  onChanged: (value) {
                    setState(() {
                      element.content = value;
                    });
                  },
                  decoration: const InputDecoration(labelText: 'Text Content'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Font Size:'),
                    Slider(
                      value: element.fontSize ?? 16.0,
                      min: 8,
                      max: 64,
                      divisions: 56,
                      onChanged: (double value) {
                        setState(() {
                          element.fontSize = value;
                        });
                      },
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('Color:'),
                    GestureDetector(
                      onTap: () {
                        // Implement color picker
                      },
                      child: Container(
                        width: 30,
                        height: 30,
                        color: element.color,
                        margin: const EdgeInsets.only(left: 8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          );
        },
      );
    }
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
            icon: const Icon(Icons.palette),
            onPressed: _changeBackgroundColor,
            tooltip: 'Change Background Color',
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _sharePoster,
            tooltip: 'Share Poster',
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
          } else if (!snapshot.hasData || _elements.isEmpty) {
            return const Center(child: Text('Template not found.'));
          } else {
            return Column(
              children: [
                Expanded(
                  child: Center(
                    child: GestureDetector(
                      onTap: () => _selectElement(null),
                      child: AspectRatio(
                        aspectRatio: _posterAspectRatio,
                        child: RepaintBoundary(
                          key: _posterKey,
                          child: Container(
                            color: _backgroundColor,
                            child: Stack(
                              children: _elements.map((e) {
                                return Positioned(
                                  left: e.x,
                                  top: e.y,
                                  child: GestureDetector(
                                    onTap: () => _selectElement(e),
                                    onPanUpdate: (details) => _onPanUpdate(e, details),
                                    child: Transform.rotate(
                                      angle: e.rotation,
                                      child: Container(
                                        decoration: _selectedElement?.id == e.id
                                            ? BoxDecoration(
                                                border: Border.all(color: Colors.blue, width: 2),
                                              )
                                            : null,
                                        child: e.type == 'text'
                                            ? SizedBox(
                                                width: e.width,
                                                child: Text(
                                                  _populateContent(e.content!, _editableFields),
                                                  style: TextStyle(
                                                    color: e.color,
                                                    fontSize: e.fontSize,
                                                    fontWeight: e.fontWeight,
                                                  ),
                                                ),
                                              )
                                            : SizedBox(
                                                width: e.width,
                                                height: e.height,
                                                child: Image.network(
                                                  e.src!,
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_selectedElement != null)
                  _buildEditingTools(_selectedElement!),
                _buildDynamicInputFields(),
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildEditingTools(ElementData element) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _editElement(element),
            tooltip: 'Edit Text',
          ),
          IconButton(
            icon: const Icon(Icons.rotate_left),
            onPressed: () {
              setState(() {
                element.rotation -= 0.1;
              });
            },
            tooltip: 'Rotate Left',
          ),
          IconButton(
            icon: const Icon(Icons.rotate_right),
            onPressed: () {
              setState(() {
                element.rotation += 0.1;
              });
            },
            tooltip: 'Rotate Right',
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicInputFields() {
    return Padding(
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
    );
  }
}