import 'dart:async'; // Dla Timer

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/food_log_provider.dart';
import '../models/food_item.dart';

class AddFoodScreen extends StatefulWidget {
  const AddFoodScreen({super.key});

  @override
  State<AddFoodScreen> createState() => _AddFoodScreenState();
}

class _AddFoodScreenState extends State<AddFoodScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // Debounce - opóźnienie wyszukiwania po wpisaniu tekstu
  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      // Wywołaj wyszukiwanie tylko jeśli kontroler jest nadal zamontowany
      if (mounted) {
        Provider.of<FoodLogProvider>(context, listen: false)
            .searchFoods(_searchController.text);
      }
    });
  }

  // Dialog do wpisania gramatury
  Future<void> _showGramsDialog(FoodItem foodItem) async {
    final formKey = GlobalKey<FormState>();
    double? grams;

    final bool? logged = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Dodaj "${foodItem.name}"'),
        content: Form(
          key: formKey,
          child: TextFormField(
            decoration: InputDecoration(
              labelText: 'Ilość (gramy)',
              suffixText: 'g',
            ),
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Podaj ilość';
              }
              final number = double.tryParse(value);
              if (number == null || number <= 0) {
                return 'Podaj poprawną liczbę dodatnią';
              }
              return null;
            },
            onSaved: (value) => grams = double.tryParse(value!),
          ),
        ),
        actions: <Widget>[
          TextButton(
            child: Text('Anuluj'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          Consumer<FoodLogProvider>( // Użyj Consumera dla przycisku
            builder: (context, foodLog, child) {
              return ElevatedButton(
                child: foodLog.isLogging
                    ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('Dodaj do dziennika'),
                onPressed: foodLog.isLogging ? null : () async {
                  if (formKey.currentState!.validate()) {
                    formKey.currentState!.save();
                    final success = await foodLog.logFoodItem(
                      foodItemId: foodItem.id,
                      grams: grams!,
                    );
                    if (mounted && success) {
                      Navigator.of(ctx).pop(true); // Zamknij dialog po sukcesie
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Dodano ${foodItem.name}!'), backgroundColor: Colors.green,)
                      );
                    } else if (mounted && !success) {
                      // Błąd został już obsłużony w providerze, ale możemy pokazać go też tutaj
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Błąd: ${foodLog.error ?? "Nie udało się dodać"}'), backgroundColor: Colors.red,)
                      );
                      // Nie zamykaj dialogu przy błędzie
                    }
                  }
                },
              );
            },
          ),
        ],
      ),
    );

    if (logged == true && mounted) {
      // Można by też zamknąć ekran AddFoodScreen po udanym dodaniu
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final foodLogProvider = Provider.of<FoodLogProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Dodaj produkt z bazy'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Wyszukaj produkt...',
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    // Wywołaj wyszukiwanie z pustym stringiem, aby wyczyścić wyniki
                    Provider.of<FoodLogProvider>(context, listen: false)
                        .searchFoods('');
                  },
                )
                    : Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          if (foodLogProvider.isLoadingSearch)
            Expanded(child: Center(child: CircularProgressIndicator()))
          else if (foodLogProvider.error != null && foodLogProvider.searchResults.isEmpty)
            Expanded(child: Center(child: Text('Błąd: ${foodLogProvider.error}')))
          else if (foodLogProvider.searchResults.isEmpty && _searchController.text.isNotEmpty)
              Expanded(child: Center(child: Text('Brak wyników dla "${_searchController.text}".')))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: foodLogProvider.searchResults.length,
                  itemBuilder: (ctx, index) {
                    final item = foodLogProvider.searchResults[index];
                    return ListTile(
                      title: Text(item.name),
                      subtitle: Text('${item.caloriesPer100g.toStringAsFixed(0)} kcal / 100g'),
                      trailing: Icon(Icons.add_circle_outline),
                      onTap: () {
                        _showGramsDialog(item);
                      },
                    );
                  },
                ),
              ),
          // TODO: Opcjonalnie przycisk "Nie znalazłeś? Dodaj nowy produkt do bazy"
        ],
      ),
    );
  }
}