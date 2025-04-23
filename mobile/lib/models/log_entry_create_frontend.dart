// lib/models/log_entry_create_frontend.dart
import 'dart:convert'; // Może niepotrzebne w samym modelu, ale dobre mieć

class LogEntryCreateFrontend {
  final String? foodItemId;
  final String? customFoodName;
  final double? customCaloriesPer100g;
  final double grams;

  LogEntryCreateFrontend({
    this.foodItemId,
    this.customFoodName,
    this.customCaloriesPer100g,
    required this.grams,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data['grams'] = grams;
    if (foodItemId != null) {
      data['food_item_id'] = foodItemId;
    } else {
      data['custom_food_name'] = customFoodName;
      data['custom_calories_per_100g'] = customCaloriesPer100g;
    }
    return data;
  }
}