import 'dart:convert';
import 'dart:typed_data';

class Customer {
  final String name;
  final String surname;
  final String phone;
  final String email;
  final String address;
  final String dob;
  final String gender;
  final List<Map<String, String>> customEntries;
  final Uint8List? imageBytes;

  Customer({
    required this.name,
    required this.surname,
    required this.phone,
    required this.email,
    required this.address,
    required this.dob,
    required this.gender,
    required this.customEntries,
    this.imageBytes,
  });

  factory Customer.fromMap(Map<String, dynamic> map) => Customer(
        name: map['name'] ?? '',
        surname: map['surname'] ?? '',
        phone: map['phone'] ?? '',
        email: map['email'] ?? '',
        address: map['address'] ?? '',
        dob: map['dob'] ?? '',
        gender: map['gender'] ?? '',
        customEntries: (map['customEntries'] as List<dynamic>? ?? [])
            .map((e) => Map<String, String>.from(e))
            .toList(),
        imageBytes: (map['image'] != null && map['image'] != "")
            ? base64Decode(map['image'])
            : null,
      );

  Map<String, dynamic> toMap() => {
        "name": name,
        "surname": surname,
        "phone": phone,
        "email": email,
        "address": address,
        "dob": dob,
        "gender": gender,
        "customEntries": customEntries,
        "image": imageBytes != null ? base64Encode(imageBytes!) : "",
      };
}