import 'dart:convert';
import 'dart:typed_data';

class Customer {
  // Core
  final String name;
  final String surname;
  final String phone;
  final String email;
  final String address;
  final String dob;      // UI-friendly DOB text (not ISO) for your current screens
  final String gender;

  // Extras
  final List<Map<String, String>> customEntries;
  final String? others;  // may contain data URL: data:image/png;base64,....
  final String? photo;   // local photo path (if any)

  // Image handling
  final Uint8List? imageBytes; // in-memory bytes for immediate UI
  final String? imageB64;      // base64 persisted in storage

  // IDs
  final String? id;       // optional unified id (string), may mirror serverId
  final String? serverId; // server-side ID (string)
  final int? fileId;      // FileId from server (int)
  final int? localId;     // local auto-increment id (for caching only)

  Customer({
    required this.name,
    required this.surname,
    required this.phone,
    required this.email,
    required this.address,
    required this.dob,
    required this.gender,
    required this.customEntries,
    this.others,
    this.photo,
    this.imageBytes,
    this.imageB64,
    this.id,
    this.serverId,
    this.fileId,
    this.localId,
  });

  // -------- Helpers --------

  static String? _stringOrNull(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString());
  }

  static Uint8List? _decodeB64Image(dynamic v) {
    if (v == null) return null;
    var s = v.toString().trim();
    if (s.isEmpty) return null;

    // Allow data URLs: data:image/png;base64,xxxx
    final commaIndex = s.indexOf(',');
    if (commaIndex != -1 &&
        s.substring(0, commaIndex).toLowerCase().contains('base64')) {
      s = s.substring(commaIndex + 1);
    }

    // Remove whitespace/newlines
    s = s.replaceAll(RegExp(r'\s'), '');
    try {
      return base64Decode(base64.normalize(s));
    } catch (_) {
      return null;
    }
  }

  static List<Map<String, String>> _coerceCustomEntries(dynamic v) {
    if (v is List) {
      return v.map<Map<String, String>>((e) {
        if (e is Map) {
          return e.map((k, val) => MapEntry(k.toString(), val?.toString() ?? ''));
        }
        return <String, String>{};
      }).toList();
    }
    return <Map<String, String>>[];
  }

  // -------- Mapping --------

  factory Customer.fromMap(Map<String, dynamic> m) {
    // Resolve IDs
    final String? idStr = _stringOrNull(
      m['id'] ??
      m['Id'] ??
      m['ID'] ??
      m['CustomerId'] ??
      m['CustomerID'] ??
      m['CustomerDataMId'] ??
      m['CustomerDataMID'] ??
      m['CustomerDataId'] ??
      m['CustomerDataID'],
    );

    final String? serverId = _stringOrNull(
      m['serverId'] ??
      m['ServerId'] ??
      m['ServerID'] ??
      idStr
    );

    // Resolve FileId (if present)
    final dynamic httpFile = m['HttpFileData'] ?? m['httpFileData'];
    final int? fileId = _toInt(
      m['fileId'] ??
      m['FileId'] ??
      (httpFile is Map ? (httpFile['Id'] ?? httpFile['FileId']) : null),
    );

    // Resolve image bytes from multiple possible sources
    Uint8List? bytes;
    // 1) direct imageBytes (bytes or base64 string)
    final dynamic imgField = m['imageBytes'];
    if (imgField is Uint8List && imgField.isNotEmpty) {
      bytes = imgField;
    } else if (imgField is String && imgField.isNotEmpty) {
      bytes = _decodeB64Image(imgField);
    }

    // 2) imageB64 (base64 string)
    String? imageB64 = _stringOrNull(m['imageB64']);
    if (bytes == null && imageB64 != null) {
      bytes = _decodeB64Image(imageB64);
    }

    // 3) Others may contain a data URL
    final String? others = _stringOrNull(m['others'] ?? m['Others']);
    if (bytes == null && others != null && others.startsWith('data:image')) {
      bytes = _decodeB64Image(others);
    }

    // If we decoded bytes but had no imageB64, create one for persistence
    imageB64 ??= (bytes != null && bytes.isNotEmpty) ? base64Encode(bytes) : null;

    return Customer(
      name: _stringOrNull(m['name'] ?? m['Name']) ?? '',
      surname: _stringOrNull(m['surname'] ?? m['Surname']) ?? '',
      phone: _stringOrNull(m['phone'] ?? m['Phone'] ?? m['PhoneNumber']) ?? '',
      email: _stringOrNull(m['email'] ?? m['Email'] ?? m['EmailId']) ?? '',
      address: _stringOrNull(m['address'] ?? m['Address']) ?? '',
      dob: _stringOrNull(m['dob'] ?? m['DOB'] ?? m['SDOB']) ?? '',
      gender: _stringOrNull(m['gender'] ?? m['Gender']) ?? '',
      customEntries: _coerceCustomEntries(m['customEntries']),
      others: others,
      photo: _stringOrNull(m['photo']),
      imageBytes: bytes,
      imageB64: imageB64,
      id: idStr,
      serverId: serverId,
      fileId: fileId,
      localId: _toInt(m['localId']),
    );
  }

  Map<String, dynamic> toMap() {
    // Prefer to include imageB64 (safe for JSON). Avoid raw imageBytes in JSON.
    final String? outB64 = imageB64 ?? (imageBytes != null && imageBytes!.isNotEmpty ? base64Encode(imageBytes!) : null);

    return <String, dynamic>{
      // IDs
      if (id != null) 'id': id,
      if (serverId != null) 'serverId': serverId,
      if (fileId != null) 'fileId': fileId,
      if (localId != null) 'localId': localId,

      // Core
      'name': name,
      'surname': surname,
      'phone': phone,
      'email': email,
      'address': address,
      'dob': dob,
      'gender': gender,

      // Extras
      'customEntries': customEntries,
      if (others != null) 'others': others,
      if (photo != null) 'photo': photo,

      // Image persistence
      if (outB64 != null) 'imageB64': outB64,
    };
  }

  Customer copyWith({
    String? name,
    String? surname,
    String? phone,
    String? email,
    String? address,
    String? dob,
    String? gender,
    List<Map<String, String>>? customEntries,
    String? others,
    String? photo,
    Uint8List? imageBytes,
    String? imageB64,
    String? id,
    String? serverId,
    int? fileId,
    int? localId,
  }) {
    return Customer(
      name: name ?? this.name,
      surname: surname ?? this.surname,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      dob: dob ?? this.dob,
      gender: gender ?? this.gender,
      customEntries: customEntries ?? this.customEntries,
      others: others ?? this.others,
      photo: photo ?? this.photo,
      imageBytes: imageBytes ?? this.imageBytes,
      imageB64: imageB64 ?? this.imageB64,
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      fileId: fileId ?? this.fileId,
      localId: localId ?? this.localId,
    );
  }
}