import 'dart:convert';
import 'package:docapp/constands/api_constands.dart';
import 'package:docapp/services/otp_Storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'services/api_Tokenstorage.dart';
import 'verification.dart';

/// Enum for UserType (still useful for dropdown)
enum UserType { employee, customer }

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  UserType? userType; // 👈 Default is null (empty dropdown)
  final TextEditingController phoneController = TextEditingController();
  bool isLoading = false;
  String apiMessage = "";

  /// Always return true no matter Employee or Customer
  bool get isUser => true;

  /// 📞 Simple phone number validator (10 digits)
  bool validatePhone(String phone) {
    final regex = RegExp(r'^\d{10}$');
    return regex.hasMatch(phone);
  }

  Future<void> loginUser() async {
    final phone = phoneController.text.trim();

    if (userType == null) {
      setState(() => apiMessage = "Please select a user type");
      return;
    }

    if (!validatePhone(phone)) {
      setState(() => apiMessage = "Please enter a valid 10-digit phone number");
      return;
    }

    setState(() {
      isLoading = true;
      apiMessage = "";
    });

    try {
      final baseUrl = await ApiConstants.baseUrl;
      final url = Uri.parse("$baseUrl/api/Auth/LoginV2");
      final requestBody = {
        "MobileNumber": phone,
        "IsUser": isUser, 
      };

      debugPrint("👉 POST $url");
      debugPrint("📦 Body Sent: ${jsonEncode(requestBody)}");

      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode(requestBody),
      );

      debugPrint("👉 Raw Response: ${response.statusCode} | ${response.body}");

      if (response.statusCode != 200) {
        setState(() => apiMessage = "Server responded with ${response.statusCode}");
        return;
      }

      late final Map<String, dynamic> data;
      try {
        data = jsonDecode(response.body);
      } catch (_) {
        setState(() => apiMessage = "Invalid JSON from server");
        return;
      }

      final bool requestSuccess =
          (data["status"] == true || data["Status"] == true);

      if (requestSuccess) {
        if (data["Response"] != null) {
          await TokenStorage.saveToken(data["Response"]);
        }
        if (data["Message"] != null) {
          await OtpStorage.saveOtp(data["Message"]);
        }

        // 👌 Navigate directly to verification (do not show message here)
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VerificationPage(
              companyLogoPath: 'assets/images/bhasha_logo.png',
              otpMessage: data["Message"] ?? "", 
              isUser: true,
            ),
          ),
        );
      } else {
        setState(() {
          apiMessage = data["ErrorMessage"] ??
              data["Message"] ??
              "Invalid phone number or login failed";
        });
      }
    } catch (e, stack) {
      debugPrint("❌ Exception: $e\n$stack");
      setState(() => apiMessage = "Error: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF4F4F4), // Background color outside container
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: SingleChildScrollView(
            child: Container(
              height: 600,
              width: 330,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color.fromARGB(255, 11, 15, 152), width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(4, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 270,
                    width: 290, 
                    child: Image.asset('/assets/images/Doc_image.png'),
                  ),
                  const SizedBox(height: 1),

                  _buildDropdownField(),
                  const SizedBox(height: 25),

                  _buildShadowTextField(
                    controller: phoneController,
                    hint: "Phone Number",
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 50),

                  _buildLoginButton(),
                  const SizedBox(height: 10),

                  if (apiMessage.isNotEmpty)
                    Text(
                      apiMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 6,
            offset: const Offset(2, 4),
          ),
        ],
      ),
      child: DropdownButtonFormField<UserType>(
        initialValue: userType,
        hint: const Text("Select User Type"),
        decoration: InputDecoration(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        items: const [
          DropdownMenuItem(
            value: UserType.employee,
            child: Text('Employee'),
          ),
          DropdownMenuItem(
            value: UserType.customer,
            child: Text('Customer'),
          ),
        ],
        onChanged: (value) => setState(() => userType = value),
      ),
    );
  }

  Widget _buildShadowTextField({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 6,
            offset: const Offset(2, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hint,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
    );
  }

  /// ✅ the button now calls loginUser()
  Widget _buildLoginButton() {
    return InkWell(
      onTap: isLoading ? null : loginUser, // disable tap when loading
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: 150,
        height: 45,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 6,
              offset: const Offset(2, 4),
            ),
          ],
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Color.fromARGB(255, 11, 15, 152)),
                  ),
                )
              : const Text(
                  'Login',
                  style: TextStyle(
                    color: Color.fromARGB(255, 11, 15, 152),
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
      ),
    );
  }
}