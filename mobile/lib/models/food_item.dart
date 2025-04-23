// lib/models/food_item.dart
class FoodItem {
  final String id; // Odpowiada _id
  final String name;
  final double caloriesPer100g;
  final double? proteinPer100g; // <-- Zmień na nullable double
  final double? carbsPer100g; // <-- Zmień na nullable double
  final double? fatPer100g; // <-- Zmień na nullable double

  FoodItem({
    required this.id,
    required this.name,
    required this.caloriesPer100g,
    this.proteinPer100g, // Może być null
    this.carbsPer100g,   // Może być null
    this.fatPer100g,     // Może być null
  });

  factory FoodItem.fromJson(Map<String, dynamic> json) {
    return FoodItem(
      id: json['_id'] as String, // Parsuj _id jako String
      name: json['name'] as String,
      caloriesPer100g: (json['calories_per_100g'] as num).toDouble(), // Parsuj jako double
      proteinPer100g: (json['protein_per_100g'] as num?)?.toDouble(), // <-- Parsuj jako nullable double
      carbsPer100g: (json['carbs_per_100g'] as num?)?.toDouble(),   // <-- Parsuj jako nullable double
      fatPer100g: (json['fat_per_100g'] as num?)?.toDouble(),     // <-- Parsuj jako nullable double
    );
  }
}