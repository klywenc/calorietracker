import 'package:flutter/material.dart';
import '../models/log_entry.dart';

class FoodLogListItem extends StatelessWidget {
  final LogEntry logEntry;

  const FoodLogListItem({Key? key, required this.logEntry}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      child: ListTile(
        leading: CircleAvatar(
          // Można dodać ikonę jedzenia lub inicjały
          child: FittedBox( // Dopasuj tekst, jeśli jest za długi
            fit: BoxFit.scaleDown,
            child: Text(
              logEntry.totalCalories.toStringAsFixed(0),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
          // backgroundColor: Colors.green[100],
        ),
        title: Text(
          logEntry.displayName, // Użyj gettera z modelu
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${logEntry.grams.toStringAsFixed(0)} g  •  ${(logEntry.timestamp)}',
        ),
        trailing: Text(
          '${logEntry.totalCalories.toStringAsFixed(0)} kcal',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[800]),
        ),
        // Można dodać onTap do edycji/usuwania w przyszłości
        // onTap: () { /* Logika edycji/usuwania */ },
      ),
    );
  }
}