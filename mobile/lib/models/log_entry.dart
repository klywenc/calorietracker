// lib/models/log_entry.dart
import 'food_item.dart'; // Upewnij się, że masz model FoodItem
import 'user.dart'; // Upewnij się, że masz model User (dla Linku do usera)
import 'package:intl/intl.dart'; // Jeśli używasz do formatowania daty/czasu
// import 'package:intl/date_time_util.dart'; // Zazwyczaj niepotrzebne

class LogEntry {
  final String id; // Odpowiada _id z MongoDB
  final UserPublic? user; // Link do użytkownika, może być null? (Zależnie od implementacji Beanie fetch_links=True)
  final FoodItem? foodItem; // <-- Zmień na nullable FoodItem
  final String? customFoodName; // Już jest nullable
  final double? customCaloriesPer100g; // Już jest nullable
  final double grams;
  final double totalCalories;
  final DateTime timestamp; // Już jest DateTime, które może być parsowane z ISO 8601

  LogEntry({
    required this.id,
    this.user, // Może być nullable
    this.foodItem, // <-- Musi być nullable
    this.customFoodName,
    this.customCaloriesPer100g,
    required this.grams,
    required this.totalCalories,
    required this.timestamp,
  });

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    // Upewnij się, że wszystkie pola JSON są prawidłowo rzutowane na typy Dart
    // używając `as Typ` dla nie-nullable i `as Typ?` lub `as num?`?.toDouble() dla nullable.
    // Pamiętaj o aliasie '_id' na 'id' w niektórych modelach.
    return LogEntry(
      id: json['_id'] as String, // _id z Mongo -> id w Dart (String)
      // Parsowanie zagnieżdżonych obiektów (jeśli fetch_links=True w API)
      user: json['user'] != null ? UserPublic.fromJson(json['user'] as Map<String, dynamic>) : null,
      foodItem: json['food_item'] != null
          ? FoodItem.fromJson(json['food_item'] as Map<String, dynamic>) // Parsuj FoodItem jeśli nie jest null
          : null, // Jeśli jest null, przypisz null
      customFoodName: json['custom_food_name'] as String?, // Parsuj jako nullable String
      customCaloriesPer100g: (json['custom_calories_per_100g'] as num?)?.toDouble(), // Parsuj jako nullable double (num -> double)
      grams: (json['grams'] as num).toDouble(), // Parsuj jako double (num -> double)
      totalCalories: (json['total_calories'] as num).toDouble(), // Parsuj jako double (num -> double)
      // Parsowanie DateTime z formatu ISO 8601
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  // *** TO JEST BRAKUJĄCY GETTER ***
  String get displayName {
    // Jeśli 'foodItem' jest dostępny (czyli wpis pochodzi z produktu z bazy)
    if (foodItem != null) {
      return foodItem!.name; // Zwróć nazwę produktu
    }
    // W przeciwnym razie (jeśli 'foodItem' jest null), wpis pochodzi z niestandardowej przekąski
    // Zwróć 'customFoodName'. Jeśli 'customFoodName' również jest null (co nie powinno się zdarzyć przy
    // poprawnej walidacji, ale na wszelki wypadek), zwróć fallback.
    return customFoodName ?? 'Niestandardowa przekąska';
  }

  // Opcjonalne gettery pomocnicze dla wyświetlania danych
  String get displayGrams {
    // Formatowanie wagi, np. "100.0g"
    return "${grams.toStringAsFixed(1)}g"; // toStringAsFixed(1) dla jednego miejsca po przecinku
  }

  String get displayCaloriesPer100g {
    // Wyświetlanie kalorii per 100g, w zależności od źródła wpisu
    if (foodItem != null) {
      return "${foodItem!.caloriesPer100g.toStringAsFixed(1)} kcal/100g";
    } else if (customCaloriesPer100g != null) {
      return "${customCaloriesPer100g!.toStringAsFixed(1)} kcal/100g";
    }
    return "N/A"; // Jeśli brak danych o kaloriach per 100g
  }

  String get displayTimestamp {
    // Formatowanie daty/czasu (wymaga importu 'package:intl/intl.dart')
    // Możesz dostosować format do swoich potrzeb
    final formatter = DateFormat('HH:mm'); // Przykład: "14:30"
    return formatter.format(timestamp.toLocal()); // Użyj toLocal() jeśli timestampy w DB są UTC
  }


}