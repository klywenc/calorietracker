// lib/models/daily_summary.dart

import 'package:flutter/foundation.dart'; // Dla kDebugMode
import 'log_entry.dart'; // Importuj model LogEntry

class DailySummary {
  final DateTime date;
  final String userId;
  final String username;
  final int? dailyCalorieGoal;
  final double totalCaloriesConsumed;
  final double? caloriesRemaining;
  final List<LogEntry> loggedEntries;

  DailySummary({
    required this.date,
    required this.userId,
    required this.username,
    this.dailyCalorieGoal,
    required this.totalCaloriesConsumed,
    this.caloriesRemaining,
    required this.loggedEntries,
  });

  factory DailySummary.fromJson(Map<String, dynamic> json) {
    if (kDebugMode) {
      print("--- Parsing DailySummary from JSON: $json ---");
    }

    // Parsowanie listy wpisów logu
    var entriesList = json['logged_entries'] as List;
    List<LogEntry> entries = entriesList
        .map((i) => LogEntry.fromJson(i as Map<String, dynamic>))
        .toList();

    return DailySummary(
      date: DateTime.parse((json['date'] as String) + 'T00:00:00Z'),
      userId: json['_id'] as String,
      username: json['username'] as String,
      dailyCalorieGoal: json['daily_calorie_goal'] as int?,
      totalCaloriesConsumed: (json['total_calories_consumed'] as num).toDouble(),
      caloriesRemaining: (json['calories_remaining'] as num?)?.toDouble(),
      loggedEntries: entries,
    );
  }

  @override
  String toString() {
    return 'DailySummary(date: $date, userId: $userId, username: $username, consumed: $totalCaloriesConsumed, goal: $dailyCalorieGoal, remaining: $caloriesRemaining, entries: ${loggedEntries.length})';
  }

// Opcjonalnie:
// String get formattedDate => DateFormat('yyyy-MM-dd').format(date);
}
