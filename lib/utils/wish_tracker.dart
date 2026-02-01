import 'package:shared_preferences/shared_preferences.dart';

class WishTracker {
  // Helper to format date as YYYY-MM-DD
  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // Generates a unique key: wish_sent_2025-01-10_9876543210_birthday
  static String _key({
    required String phone,
    required String type, // 'birthday' or 'anniversary'
    DateTime? date,
  }) {
    final d = date ?? DateTime.now();
    // Normalize inputs to lowercase and trim to avoid duplicates
    return 'wish_sent_${_dateKey(d)}_${phone.trim()}_${type.trim().toLowerCase()}';
  }

  // Mark a specific event type as done for today
  static Future<void> markDone({
    required String phone,
    required String type, // Pass 'birthday' or 'anniversary'
    DateTime? date,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(phone: phone, type: type, date: date), true);
  }

  // Check if a specific event type is done for today
  static Future<bool> isDone({
    required String phone,
    required String type, // Pass 'birthday' or 'anniversary'
    DateTime? date,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    // Defaults to false if not found
    return prefs.getBool(_key(phone: phone, type: type, date: date)) ?? false;
  }
}