// lib/verificationpage.dart
import 'dart:convert';
import 'package:docapp/constands/api_constands.dart';
import 'package:docapp/dashboardpage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'services/api_Tokenstorage.dart';

class VerificationPage extends StatefulWidget {
  final String companyLogoPath;
  final String otpMessage;
  final bool isUser;

  const VerificationPage({
    super.key,
    required this.companyLogoPath,
    required this.otpMessage,
    required this.isUser,
  });

  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage> {
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;

  Future<void> verifyOTP() async {
    final otp = _otpControllers.map((c) => c.text).join();
    if (otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter all 6 digits')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final existingToken = await TokenStorage.getToken() ?? "";

      if (existingToken.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Session expired. Please login again.")),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const Dashboardpage()),
          );
        }
        return;
      }

      final baseUrl = ApiConstants.baseUrl;

      final payload = {
        "otp": otp,
        "isUser": widget.isUser,
        "token": existingToken,
      };

      debugPrint("📤 Sending OTP Request: ${jsonEncode(payload)}");

      final response = await http.post(
        Uri.parse("$baseUrl/api/Auth/OtpVerification"),
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "Authorization": "Bearer $existingToken",
        },
        body: jsonEncode(payload),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      debugPrint("📥 OTP Verification Response: $data");

      await VerificationTokenStorage.setOtpVerificationResponse(data);
      final bool ok = response.statusCode == 200 &&
          (data["Status"] == true) &&
          (data["StatusCode"] == 200);

      if (!ok) {
        if (!mounted) return;
        final msg =
            (data["Message"] ?? data["ErrorMessage"] ?? "Invalid OTP").toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }

      final resp = (data["Response"] is Map)
          ? Map<String, dynamic>.from(data["Response"])
          : <String, dynamic>{};

      // Save user profile
      await VerificationTokenStorage.setUserProfile(resp);

      // Save new token if provided
      final newToken = (resp["Token"] as String?)?.trim();
      if (newToken != null && newToken.isNotEmpty) {
        await VerificationTokenStorage.setToken(newToken);
      }

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => Dashboardpage()),
        (route) => false,
      );
    } catch (e, st) {
      debugPrint("OTP verify error: $e\n$st");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    for (var c in _otpControllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Widget buildOTPBox(int index) {
    return Container(
      width: 45,
      height: 55,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFA9E265), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.25),
            blurRadius: 5,
            offset: const Offset(3, 4),
          ),
        ],
      ),
      child: Center(
        child: TextField(
          controller: _otpControllers[index],
          focusNode: _focusNodes[index],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            counterText: '',
          ),
          onChanged: (value) {
            if (value.isNotEmpty && index < 5) {
              FocusScope.of(context).requestFocus(_focusNodes[index + 1]);
            } else if (value.isEmpty && index > 0) {
              FocusScope.of(context).requestFocus(_focusNodes[index - 1]);
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(30),
          margin: const EdgeInsets.symmetric(horizontal: 25),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: const Color(0xFFA9E265), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(5, 6),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                SizedBox(
                  height: 150,
                  child: widget.companyLogoPath.startsWith('http')
                      ? Image.network(widget.companyLogoPath, fit: BoxFit.contain)
                      : Image.asset(widget.companyLogoPath, fit: BoxFit.contain),
                ),
                const SizedBox(height: 20),

                // OTP Message
                Text(
                  widget.otpMessage.isNotEmpty
                      ? "Testing OTP: ${widget.otpMessage}"
                      : "Enter the 6-digit OTP sent to your mobile number",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: Colors.black87),
                ),
                const SizedBox(height: 25),

                // OTP Input Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(6, buildOTPBox),
                ),
                const SizedBox(height: 40),

                // Verify Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : verifyOTP,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFFA9E265),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                        side: const BorderSide(color: Color(0xFFA9E265)),
                      ),
                      elevation: 6,
                      shadowColor: Colors.black.withOpacity(0.25),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFA9E265),
                            ),
                          )
                        : const Text(
                            'Verify',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFA9E265),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}