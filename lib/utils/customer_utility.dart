import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:docapp/model/customer.dart' as model;

ImageProvider? customerImageProvider(model.Customer c) {
  // Try local file path from 'photo' (persisted)
  try {
    final map = c.toMap();
    final photo = map['photo'];
    if (photo is String && photo.isNotEmpty) {
      final f = File(photo);
      if (f.existsSync()) return FileImage(f);
    }
  } catch (_) {}

  // In-memory bytes
  if (c.imageBytes != null && c.imageBytes!.isNotEmpty) {
    return MemoryImage(c.imageBytes!);
  }

  // Data URL
  if (c.others is String) {
    final s = c.others as String;
    if (s.startsWith('data:image')) {
      try {
        final base64Part = s.split(',').last;
        final bytes = base64Decode(base64.normalize(base64Part));
        return MemoryImage(bytes);
      } catch (_) {}
    }
    // Network image (if provided)
    if (s.startsWith('http://') || s.startsWith('https://')) {
      return NetworkImage(s);
    }
  }

  return null;
}