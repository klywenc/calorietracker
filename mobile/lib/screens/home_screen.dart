import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // Dla DateFormat
import '../providers/auth_provider.dart';
import '../providers/food_log_provider.dart';
import '../widgets/food_log_list_item.dart';
import 'add_food_screen.dart';
import 'add_snack_screen.dart';

class HomeScreen extends StatelessWidget { // Może być StatelessWidget
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Pobierz dostawców bez nasłuchiwania, jeśli potrzebne tylko do akcji
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: Text('Twój Dziennik Kalorii'),
        actions: [
          IconButton( // Przycisk do odświeżania
            icon: Icon(Icons.refresh),
            tooltip: 'Odśwież podsumowanie',
            onPressed: () {
              // Wywołaj odświeżanie w providerze
              Provider.of<FoodLogProvider>(context, listen: false).fetchDailySummary();
            },
          ),
          IconButton(
            icon: Icon(Icons.logout),
            tooltip: 'Wyloguj',
            onPressed: () {
              authProvider.logout();
              // Navigator.of(context).pushReplacementNamed('/'); // Można wymusić powrót
            },
          ),
        ],
      ),
      body: Consumer<FoodLogProvider>( // Użyj Consumer do nasłuchiwania zmian
        builder: (ctx, foodLogProvider, _) {
          if (foodLogProvider.isLoadingSummary && foodLogProvider.dailySummary == null) {
            // Pokaż ładowanie tylko przy pierwszym ładowaniu (gdy summary jest null)
            return Center(child: CircularProgressIndicator());
          } else if (foodLogProvider.error != null && foodLogProvider.dailySummary == null) {
            // Pokaż błąd tylko jeśli nie udało się załadować początkowego podsumowania
            return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Wystąpił błąd: ${foodLogProvider.error}', textAlign: TextAlign.center),
                )
            );
          } else if (foodLogProvider.dailySummary == null) {
            // Stan po zalogowaniu, ale przed pobraniem danych (lub błąd przy odświeżaniu)
            // Można tu pokazać delikatniejszy wskaźnik ładowania lub komunikat
            return Center(child: Text('Pobieranie danych...'));
          } else {
            // Mamy dane, wyświetl podsumowanie
            return _buildSummaryContent(context, foodLogProvider);
          }
        },
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'add_food_db', // Unikalny tag
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => AddFoodScreen()));
            },
            label: Text("Dodaj z bazy"),
            icon: Icon(Icons.search),
            tooltip: 'Wyszukaj i dodaj produkt z bazy',
          ),
          SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'add_snack_custom', // Unikalny tag
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => AddSnackScreen()));
            },
            label: Text("Dodaj przekąskę"),
            icon: Icon(Icons.add),
            tooltip: 'Dodaj własny produkt/przekąskę',
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryContent(BuildContext context, FoodLogProvider foodLogProvider) {
    final summary = foodLogProvider.dailySummary!; // Wiemy, że nie jest null tutaj
    // Pobierz userId raz, zamiast wielokrotnie w onRefresh
    final userId = Provider.of<AuthProvider>(context, listen: false).userId;

    return RefreshIndicator(
      onRefresh: () async {
        // Sprawdź czy userId istnieje przed odświeżeniem
        if (userId != null) {
          await foodLogProvider.fetchDailySummary();
        } else {
          print("Cannot refresh, userId is null.");
          // Opcjonalnie pokaż SnackBar
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Błąd odświeżania: brak ID użytkownika.'))
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pokaż wskaźnik ładowania przy odświeżaniu, jeśli summary już istnieje
            if (foodLogProvider.isLoadingSummary)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            Text('Podsumowanie dnia (${DateFormat('yyyy-MM-dd', 'pl_PL').format(summary.date)})',
                style: Theme.of(context).textTheme.headlineSmall),
            SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatCard('Spożyte', summary.totalCaloriesConsumed.toStringAsFixed(0), 'kcal'),
                if (summary.dailyCalorieGoal != null)
                  _buildStatCard('Cel', summary.dailyCalorieGoal!.toString(), 'kcal'),
                if (summary.caloriesRemaining != null)
                  _buildStatCard('Pozostało', summary.caloriesRemaining!.toStringAsFixed(0), 'kcal',
                      color: summary.caloriesRemaining! < 0
                          ? Colors.red.shade100
                          : (summary.caloriesRemaining! < summary.dailyCalorieGoal! * 0.1) // np. mniej niż 10% celu
                          ? Colors.orange.shade100
                          : Colors.green.shade100),
              ],
            ),
            SizedBox(height: 20),
            Text('Dzisiejsze wpisy:', style: Theme.of(context).textTheme.titleMedium),
            Expanded(
              child: summary.loggedEntries.isEmpty
                  ? Center(child: Text('Brak wpisów na dzisiaj.\nDodaj pierwszy posiłek!', textAlign: TextAlign.center,))
                  : ListView.builder(
                itemCount: summary.loggedEntries.length,
                itemBuilder: (ctx, index) {
                  // Odwróć kolejność, aby najnowsze były na górze
                  final entry = summary.loggedEntries[summary.loggedEntries.length - 1 - index];
                  return FoodLogListItem(logEntry: entry);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, String unit, {Color? color}) {
    return Card(
      color: color,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
            SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(unit, style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}