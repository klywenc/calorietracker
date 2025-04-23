// lib/models/food_item_create.dart
import 'dart:convert';

class FoodItemCreate {
  final String name;
  final double caloriesPer100g;
  final double? proteinPer100g;
  final double? carbsPer100g;
  final double? fatPer100g;

  FoodItemCreate({
    required this.name,
    required this.caloriesPer100g,
    this.proteinPer100g,
    this.carbsPer100g,
    this.fatPer100g,
  });

  // Metoda do konwersji obiektu na mapę, która może być użyta w jsonEncode
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'name': name,
      'calories_per_100g': caloriesPer100g,
    };
    if (proteinPer100g != null) {
      data['protein_per_100g'] = proteinPer100g;
    }
    if (carbsPer100g != null) {
      data['carbs_per_100g'] = carbsPer100g;
    }
    if (fatPer100g != null) {
      data['fat_per_100g'] = fatPer100g;
    }
    return data;
  }

// Opcjonalnie możesz dodać fromJson(), jeśli kiedykolwiek będziesz musiał
// dekodować ten typ (raczej rzadko w przypadku modeli Create)
}