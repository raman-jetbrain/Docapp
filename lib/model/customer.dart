import 'dart:convert';
import 'dart:typed_data';

class Customer {
  // Core
  final String name;
  final String surname;
  final String phone;
  final String email;
  final String address;
  /// UI-friendly DOB text (raw string from API; parsing/formatting is done in UI).
  final String dob;
  final String gender;

  // Extras
  final List<Map<String, String>> customEntries;
  /// May contain data URL: data:image/png;base64,xxxx
  final String? others;
  /// Local photo path (if any)
  final String? photo;

  // Image handling
  /// In-memory bytes for immediate UI
  final Uint8List? imageBytes;
  /// Base64 persisted in storage
  final String? imageB64;

  // IDs
  /// Unified id (string), may mirror serverId / CustomerDataMId
  final String? id;
  /// Server-side ID (string)
  final String? serverId;
  /// FileId from server (int)
  final int? fileId;
  /// Local auto-increment id (for caching only)
  final int? localId;
  /// ParentCustomerDataId from API (non-null indicates this record is a child)
  final int? parentCustomerDataId;

  // Marriage
  /// "Married", "Single", etc.
  final String? maritalStatus;
  /// e.g. "2010-10-11T06:30:00"
  final String? marriedDate;

  Customer({
    // core
    required this.name,
    required this.surname,
    required this.phone,
    required this.email,
    required this.address,
    required this.dob,
    required this.gender,
    required this.customEntries,
    // extras
    this.others,
    this.photo,
    // image
    this.imageBytes,
    this.imageB64,
    // ids
    this.id,
    this.serverId,
    this.fileId,
    this.localId,
    this.parentCustomerDataId,
    // marriage
    this.maritalStatus,
    this.marriedDate,
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

  /// Safer base64 decode for image fields
  static Uint8List? _decodeB64Image(dynamic v) {
    if (v == null) return null;
    var s = v.toString().trim();
    if (s.isEmpty) return null;

    // Skip common placeholder values
    final lower = s.toLowerCase();
    if (lower == 'string' || lower == 'null' || lower == 'undefined') {
      return null;
    }
    if (s.startsWith('<base64:')) return null;

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
          return e.map(
            (k, val) => MapEntry(k.toString(), val?.toString() ?? ''),
          );
        }
        return <String, String>{};
      }).toList();
    }
    return <Map<String, String>>[];
  }

  // -------- Mapping --------

  factory Customer.fromMap(Map<String, dynamic> m) {
    // ----- IDs -----
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
      m['serverId'] ?? m['ServerId'] ?? m['ServerID'] ?? idStr,
    );

    // Resolve FileId (if present, including from nested HttpFileData)
    final dynamic httpFile = m['HttpFileData'] ?? m['httpFileData'];
    final int? fileId = _toInt(
      m['fileId'] ??
          m['FileId'] ??
          (httpFile is Map ? (httpFile['Id'] ?? httpFile['FileId']) : null),
    );

    // ParentCustomerDataId (indicates this record is a child when non-null)
    final int? parentId = _toInt(
      m['parentCustomerDataId'] ??
          m['ParentCustomerDataId'] ??
          m['ParentId'] ??
          m['parentId'],
    );

    // Marriage
    final String? maritalStatus = _stringOrNull(
      m['maritalStatus'] ??
          m['MaritalStatus'] ?? // correct spelling
          m['MartialStatus'],   // API typo
    );
    final String? marriedDate = _stringOrNull(
      m['marriedDate'] ?? m['MarriedDate'],
    );

    // ----- Image bytes / base64 -----
    Uint8List? bytes;
    String? imageB64;

    // 1) direct imageBytes (may be bytes or base64 string)
    final dynamic imgField = m['imageBytes'];
    if (imgField is Uint8List && imgField.isNotEmpty) {
      bytes = imgField;
    } else if (imgField is String && imgField.isNotEmpty) {
      final b = _decodeB64Image(imgField);
      if (b != null && b.isNotEmpty) bytes = b;
    }

    // 2) imageB64 (base64 string, common for persistence)
    imageB64 = _stringOrNull(m['imageB64']);
    if (bytes == null && imageB64 != null) {
      final b = _decodeB64Image(imageB64);
      if (b != null && b.isNotEmpty) bytes = b;
    }

    // 3) Others may contain a data URL from API
    final String? others = _stringOrNull(m['others'] ?? m['Others']);
    if (bytes == null &&
        others != null &&
        others.toLowerCase().startsWith('data:image')) {
      final b = _decodeB64Image(others);
      if (b != null && b.isNotEmpty) bytes = b;
    }

    // If we decoded bytes but had no base64, create one for persistence
    imageB64 ??=
        (bytes != null && bytes.isNotEmpty) ? base64Encode(bytes) : null;

    // ----- Core fields -----
    final String name =
        _stringOrNull(m['name'] ?? m['Name'] ?? m['firstName'] ?? m['FirstName']) ??
            '';
    final String surname =
        _stringOrNull(m['surname'] ?? m['Surname'] ?? m['lastName'] ?? m['LastName']) ??
            '';
    final String phone = _stringOrNull(
          m['phone'] ??
              m['Phone'] ??
              m['phoneNumber'] ??
              m['PhoneNumber'] ??
              m['mobile'] ??
              m['Mobile'] ??
              m['mobileNumber'] ??
              m['MobileNumber'],
        ) ??
        '';

    final String email = _stringOrNull(
          m['email'] ??
              m['Email'] ??
              m['EmailId'] ??
              m['EmailID'] ??
              m['emailId'] ??
              m['emailID'],
        ) ??
        '';

    final String address =
        _stringOrNull(m['address'] ?? m['Address'] ?? m['addr'] ?? m['Addr']) ??
            '';

    // DOB: normalize from many possible API keys into single `dob` field
    final String dob = _stringOrNull(
          m['dob'] ??
              m['DOB'] ??
              m['SDOB'] ??
              m['dateOfBirth'] ??
              m['DateOfBirth'] ??
              m['birthDate'] ??
              m['BirthDate'] ??
              m['birthday'] ??
              m['Birthday'],
        ) ??
        '';

    final String gender = _stringOrNull(
          m['gender'] ?? m['Gender'] ?? m['sex'] ?? m['Sex'],
        ) ??
        '';

    // Custom entries: accept multiple key variants
    final List<Map<String, String>> customEntries = _coerceCustomEntries(
      m['customEntries'] ??
          m['CustomEntries'] ??
          m['custom_fields'] ??
          m['CustomFields'],
    );

    final String? photo = _stringOrNull(m['photo'] ?? m['Photo']);

    return Customer(
      // core
      name: name,
      surname: surname,
      phone: phone,
      email: email,
      address: address,
      dob: dob,
      gender: gender,
      customEntries: customEntries,
      // extras
      others: others,
      photo: photo,
      // image
      imageBytes: bytes,
      imageB64: imageB64,
      // ids
      id: idStr,
      serverId: serverId,
      fileId: fileId,
      localId: _toInt(m['localId']),
      parentCustomerDataId: parentId,
      // marriage
      maritalStatus: maritalStatus,
      marriedDate: marriedDate,
    );
  }

  Map<String, dynamic> toMap() {
    // Prefer to include imageB64 (safe for JSON). Avoid raw imageBytes in JSON.
    final String? outB64 = imageB64 ??
        (imageBytes != null && imageBytes!.isNotEmpty
            ? base64Encode(imageBytes!)
            : null);

    return <String, dynamic>{
      // IDs
      if (id != null) 'id': id,
      if (serverId != null) 'serverId': serverId,
      if (fileId != null) 'fileId': fileId,
      if (localId != null) 'localId': localId,
      if (parentCustomerDataId != null)
        'parentCustomerDataId': parentCustomerDataId,

      // Marriage
      if (maritalStatus != null) 'maritalStatus': maritalStatus,
      if (marriedDate != null) 'marriedDate': marriedDate,

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
    int? parentCustomerDataId,
    String? maritalStatus,
    String? marriedDate,
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
      parentCustomerDataId:
          parentCustomerDataId ?? this.parentCustomerDataId,
      maritalStatus: maritalStatus ?? this.maritalStatus,
      marriedDate: marriedDate ?? this.marriedDate,
    );
  }
}