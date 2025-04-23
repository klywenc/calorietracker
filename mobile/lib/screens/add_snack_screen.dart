// Plik: lib/screens/add_snack_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/food_log_provider.dart';

// *** POPRAWNA NAZWA KLASY ***
class AddSnackScreen extends StatefulWidget {
  const AddSnackScreen({super.key}); // Poprawiony konstruktor dla nowszych wersji Flutter

  @override
  // *** POPRAWNA NAZWA KLASY STATE ***
  State<AddSnackScreen> createState() => _AddSnackScreenState();
}

// *** POPRAWNA NAZWA KLASY STATE ***
class _AddSnackScreenState extends State<AddSnackScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _name;
  double? _caloriesPer100g;
  double? _grams;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    _formKey.currentState!.save();

    final foodLogProvider = Provider.of<FoodLogProvider>(context, listen: false);
    final success = await foodLogProvider.logFoodItem(
      customFoodName: _name!,
      customCaloriesPer100g: _caloriesPer100g!,
      grams: _grams!,
    );

    if (mounted && success) {
      Navigator.of(context).pop(); // Wróć do poprzedniego ekranu
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dodano $_name!'), backgroundColor: Colors.green,)
      );
    } else if (mounted && !success) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd: ${foodLogProvider.error ?? "Nie udało się dodać"}'), backgroundColor: Colors.red,)
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Dodaj własną przekąskę'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: <Widget>[
              TextFormField(
                decoration: InputDecoration(labelText: 'Nazwa produktu/przekąski'),
                textCapitalization: TextCapitalization.sentences,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Podaj nazwę';
                  }
                  return null;
                },
                onSaved: (value) => _name = value,
              ),
              SizedBox(height: 12),
              TextFormField(
                decoration: InputDecoration(
                  labelText: 'Kalorie na 100g',
                  suffixText: 'kcal / 100g',
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Podaj kalorie';
                  }
                  final number = double.tryParse(value);
                  if (number == null || number <= 0) {
                    return 'Podaj poprawną liczbę dodatnią';
                  }
                  return null;
                },
                onSaved: (value) => _caloriesPer100g = double.tryParse(value!),
              ),
              SizedBox(height: 12),
              TextFormField(
                decoration: InputDecoration(
                  labelText: 'Spożyta ilość (gramy)',
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
                onSaved: (value) => _grams = double.tryParse(value!),
              ),
              SizedBox(height: 30),
              Consumer<FoodLogProvider>( // Użyj Consumera dla przycisku
                  builder: (context, foodLog, child) {
                    return ElevatedButton(
                      onPressed: foodLog.isLogging ? null : _submit,
                      child: foodLog.isLogging
                          ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text('Dodaj do dziennika'),
                    );
                  }
              ),
            ],
          ),
        ),
      ),
    );
  }
}