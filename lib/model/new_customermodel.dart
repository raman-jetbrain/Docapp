// lib/model/customermodel.dart
import 'dart:convert';
import 'dart:typed_data';

class Customer {
  final String id;
  final String serverId;
  final String name;
  final String surname;
  final String phone;
  final String email;
  final String address;
  final String gender;
  final dynamic others;

  // Not serialized directly; we persist as base64 string (imageB64)
  final Uint8List? imageBytes;

  Customer({
    required this.id,
    required this.serverId,
    required this.name,
    required this.surname,
    required this.phone,
    required this.email,
    required this.address,
    required this.gender,
    required this.others,
    required this.imageBytes,
  });

  factory Customer.fromMap(Map<String, dynamic> m) {
    Uint8List? bytes;
    // Allow either raw bytes passed at runtime, or base64 persisted in storage
    if (m['imageBytes'] is Uint8List) {
      bytes = m['imageBytes'] as Uint8List;
    } else if (m['imageB64'] is String && (m['imageB64'] as String).isNotEmpty) {
      try {
        bytes = base64Decode(m['imageB64'] as String);
      } catch (_) {}
    }

    return Customer(
      id: (m['id'] ?? m['Id'] ?? '').toString(),
      serverId: (m['serverId'] ?? m['ServerId'] ?? m['Id'] ?? '').toString(),
      name: (m['name'] ?? m['Name'] ?? '').toString(),
      surname: (m['surname'] ?? m['Surname'] ?? '').toString(),
      phone: (m['phone'] ?? m['PhoneNumber'] ?? '').toString(),
      email: (m['email'] ?? m['EmailId'] ?? '').toString(),
      address: (m['address'] ?? m['Address'] ?? '').toString(),
      gender: (m['gender'] ?? m['Gender'] ?? '').toString(),
      others: m['others'] ?? m['Others'],
      imageBytes: bytes,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'serverId': serverId,
      'name': name,
      'surname': surname,
      'phone': phone,
      'email': email,
      'address': address,
      'gender': gender,
      'others': others,
      'imageB64': imageBytes != null ? base64Encode(imageBytes!) : null,
    };
  }
}