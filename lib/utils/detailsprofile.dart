import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:docapp/api/api_constant.dart';
import 'package:docapp/model/customer.dart' as model;
import 'package:docapp/storage/Token_storage.dart';

// ---------------- Basic helpers ----------------

String _normalizeBase(String base) {
  var b = base.trim();
  if (b.endsWith('/')) b = b.substring(0, b.length - 1);
  return b;
}

String _absoluteFromBase(String pathOrUrl) {
  final p = pathOrUrl.trim();
  if (p.startsWith('http://') || p.startsWith('https://')) return p;

  final base = _normalizeBase(ApiConstants.baseUrl);
  if (p.startsWith('/')) return '$base$p';
  // Assume it's a file name under /uploads
  return '$base/uploads/${Uri.encodeComponent(p)}';
}

String? _extractBase64FromDataUrl(String dataUrl) {
  final i = dataUrl.indexOf('base64,');
  if (i == -1) return null;
  return dataUrl.substring(i + 7).trim();
}

Uint8List? _bytesFromAny(dynamic src) {
  try {
    if (src == null) return null;
    if (src is Uint8List) return src;
    if (src is List<int>) return Uint8List.fromList(src);
    if (src is String && src.isNotEmpty) {
      final b64 = src.startsWith('data:') ? _extractBase64FromDataUrl(src) : src;
      if (b64 == null || b64.isEmpty) return null;
      return base64Decode(b64);
    }
  } catch (_) {}
  return null;
}

bool _isLocalFilePath(String p) {
  if (p.startsWith('file://')) return true;
  if (p.startsWith('/')) return true; // Unix-like absolute path
  // Windows absolute path e.g., C:\ or C:/
  return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(p);
}

// Public helper for simple cases (bytes, data URLs, local file, or public URLs)
ImageProvider? customerImageProvider(model.Customer c) {
  final bytes = _bytesFromAny(c.imageBytes);
  if (bytes != null && bytes.isNotEmpty) return MemoryImage(bytes);

  final photo = (c.photo ?? '').trim();
  if (photo.isEmpty) return null;

  if (photo.startsWith('data:image')) {
    final b64 = _extractBase64FromDataUrl(photo);
    if (b64 != null && b64.isNotEmpty) {
      try {
        return MemoryImage(base64Decode(b64));
      } catch (_) {}
    }
  }

  // Local file path
  if (!kIsWeb && _isLocalFilePath(photo)) {
    try {
      final path = photo.startsWith('file://') ? Uri.parse(photo).toFilePath() : photo;
      final f = File(path);
      if (f.existsSync()) return FileImage(f);
    } catch (_) {}
  }

  final url = _absoluteFromBase(photo);
  return NetworkImage(url);
}

// ---------------- Authorized fetch + cache (for protected images) ----------------

final Map<String, Uint8List> _authImageCache = {}; // in-memory cache

bool _sameHost(String a, String b) {
  final ua = Uri.tryParse(a);
  final ub = Uri.tryParse(b);
  if (ua == null || ub == null) return false;
  return ua.host.toLowerCase() == ub.host.toLowerCase();
}

Future<Uint8List?> _fetchImageBytesWithAuth(String url) async {
  try {
    if (_authImageCache.containsKey(url)) {
      return _authImageCache[url];
    }

    final token = await TokenStorage.getToken();
    final base = ApiConstants.baseUrl;
    final needsAuth = token != null && token.isNotEmpty && _sameHost(url, base);

    final headers = <String, String>{'Accept': 'image/*'};
    if (needsAuth) {
      headers['Authorization'] = token.startsWith('Bearer ') ? token : 'Bearer $token';
    }

    final res = await http.get(Uri.parse(url), headers: headers);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final bytes = res.bodyBytes;
      if (bytes.isNotEmpty) {
        _authImageCache[url] = bytes;
        return bytes;
      }
    }
  } catch (_) {
    // Ignore; fallback happens
  }
  return null;
}

// Async resolver that tries: bytes/data → file → authorized fetch → network
Future<ImageProvider?> resolveAuthorizedCustomerImage(model.Customer c) async {
  final direct = customerImageProvider(c);
  if (direct == null) return null;

  // Already bytes or local file
  if (direct is MemoryImage || direct is FileImage) return direct;

  // Try fetching with Authorization if needed
  if (direct is NetworkImage) {
    final url = direct.url;
    final bytes = await _fetchImageBytesWithAuth(url);
    if (bytes != null && bytes.isNotEmpty) return MemoryImage(bytes);
    return direct; // Fallback to plain network
  }

  return direct;
}

// ---------------- Widgets ----------------

class CustomerAvatar extends StatefulWidget {
  final model.Customer customer;
  final double radius;
  final Color? bgColor;
  final Color? iconColor;
  final IconData placeholderIcon;

  const CustomerAvatar({
    super.key,
    required this.customer,
    this.radius = 30,
    this.bgColor,
    this.iconColor,
    this.placeholderIcon = Icons.person,
  });

  @override
  State<CustomerAvatar> createState() => _CustomerAvatarState();
}

class _CustomerAvatarState extends State<CustomerAvatar> {
  ImageProvider? _provider;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant CustomerAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customer.photo != widget.customer.photo ||
        oldWidget.customer.imageBytes != widget.customer.imageBytes) {
      _resolve();
    }
  }

  Future<void> _resolve() async {
    setState(() => _loading = true);

    // 1) If bytes/data URL/local file -> direct provider via helper
    final direct = customerImageProvider(widget.customer);
    if (direct != null && (direct is MemoryImage || direct is FileImage)) {
      if (!mounted) return;
      setState(() {
        _provider = direct;
        _loading = false;
      });
      return;
    }

    // 2) If we have a URL, try to fetch with Authorization if same host
    final photo = (widget.customer.photo ?? '').trim();
    if (photo.isNotEmpty) {
      final url = _absoluteFromBase(photo);

      // Try authorized fetch (for protected endpoints)
      final bytes = await _fetchImageBytesWithAuth(url);
      if (mounted && bytes != null && bytes.isNotEmpty) {
        setState(() {
          _provider = MemoryImage(bytes);
          _loading = false;
        });
        return;
      }

      // 3) Fallback to plain NetworkImage (for public images/CDN)
      if (!mounted) return;
      setState(() {
        _provider = NetworkImage(url);
        _loading = false;
      });
      return;
    }

    // 4) No image available
    if (!mounted) return;
    setState(() {
      _provider = null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.bgColor ?? Colors.blue.shade50;
    final iconC = widget.iconColor ?? Colors.blueGrey;

    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: bg,
      backgroundImage: _provider,
      child: (_provider == null)
          ? (_loading
              ? SizedBox(
                  height: widget.radius,
                  width: widget.radius,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(widget.placeholderIcon, size: widget.radius, color: iconC))
          : null,
    );
  }
}

class CustomerPhoto extends StatefulWidget {
  final model.Customer customer;
  final BoxFit fit;
  final Widget? placeholder;

  const CustomerPhoto({
    super.key,
    required this.customer,
    this.fit = BoxFit.cover,
    this.placeholder,
  });

  @override
  State<CustomerPhoto> createState() => _CustomerPhotoState();
}

class _CustomerPhotoState extends State<CustomerPhoto> {
  ImageProvider? _provider;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CustomerPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customer.photo != widget.customer.photo ||
        oldWidget.customer.imageBytes != widget.customer.imageBytes) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final p = await resolveAuthorizedCustomerImage(widget.customer);
    if (!mounted) return;
    setState(() {
      _provider = p;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_provider != null) {
      return Image(image: _provider!, fit: widget.fit);
    }
    if (_loading) {
      return Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return widget.placeholder ?? const SizedBox.shrink();
  }
}