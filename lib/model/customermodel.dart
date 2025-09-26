import 'dart:convert';
import 'dart:typed_data';

class Customer {

  final String name;
  final String surname;
  final String phone;
  final String email;
  final Uint8List? imageBytes;
  final String? address;
  final String? dob;
  final String? gender;
  final List<Map<String, String>>? customEntries;

  var others;

  var id;

  Customer({
    required this.name,
    required this.surname,
    required this.phone,
    this.email = '',
    this.imageBytes,
    this.address,
    this.dob,
    this.gender,
    this.customEntries, String? photo,
  });

  // 🔹 Factory for decoding from stored map
  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      name: map['name'] ?? '',
      surname: map['surname'] ?? '',
      phone: map['phone'] ?? '',
      email: map['email'] ?? '',
      imageBytes: map['image'] != null && (map['image'] as String).isNotEmpty
          ? Uint8List.fromList(base64Decode(map['image']))
          : null,
      address: map['address'],
      dob: map['dob'],
      gender: map['gender'],
      customEntries: map['customEntries'] != null
          ? List<Map<String, String>>.from(
              (map['customEntries'] as List)
                  .map((e) => Map<String, String>.from(e)),
            )
          : null,
    );
  }



  // 🔹 Convert object to Map for saving into SharedPreferences/DB
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'surname': surname,
      'phone': phone,
      'email': email,
      'image': imageBytes != null ? base64Encode(imageBytes!) : '',
      'address': address,
      'dob': dob,
      'gender': gender,
      'customEntries': customEntries,
    };
  }
}