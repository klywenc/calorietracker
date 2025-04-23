import 'package:flutter/foundation.dart';

// Odpowiada UserPublic z FastAPI
class UserPublic {
  final String id;
  final String username;
  final String? email;
  final int? dailyCalorieGoal;
  final bool isActive;

  UserPublic({
    required this.id,
    required this.username,
    this.email,
    this.dailyCalorieGoal,
    required this.isActive,
  });

  factory UserPublic.fromJson(Map<String, dynamic> json) {
    return UserPublic(
      id: json['_id'] ?? json['id'], // Obsługa _id z MongoDB
      username: json['username'],
      email: json['email'],
      dailyCalorieGoal: json['daily_calorie_goal'],
      isActive: json['is_active'] ?? true, // Domyślnie true jeśli brak
    );
  }

  @override
  String toString() {
    return 'UserPublic(id: $id, username: $username, email: $email, dailyCalorieGoal: $dailyCalorieGoal, isActive: $isActive)';
  }
}