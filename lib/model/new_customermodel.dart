// lib/model/customermodel.dart
import 'dart:typed_data';

class Customer {
  final String id; // REQUIRED for delete
  final String name;
  final String surname;
  final String phone;
  final String email;
  final String address;
  final String gender;
  final dynamic others; // can be String or anything you use
  final Uint8List? imageBytes;

  Customer({
    required this.id,
    required this.name,
    required this.surname,
    required this.phone,
    required this.email,
    required this.address,
    required this.gender,
    this.others,
    this.imageBytes,
  });

  factory Customer.fromMap(Map<String, dynamic> m) {
    return Customer(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      surname: (m['surname'] ?? '').toString(),
      phone: (m['phone'] ?? '').toString(),
      email: (m['email'] ?? '').toString(),
      address: (m['address'] ?? '').toString(),
      gender: (m['gender'] ?? '').toString(),
      others: m['others'],
      imageBytes: m['imageBytes'] is Uint8List ? m['imageBytes'] as Uint8List : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'surname': surname,
      'phone': phone,
      'email': email,
      'address': address,
      'gender': gender,
      'others': others,
      'imageBytes': imageBytes,
    };
  }
}