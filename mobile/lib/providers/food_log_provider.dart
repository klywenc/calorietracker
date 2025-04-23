import 'package:flutter/foundation.dart'; // Dla kDebugMode
import '../models/daily_summary.dart'; // Importuj model DailySummary
import '../models/food_item.dart'; // Importuj model FoodItem
import '../models/log_entry.dart'; // Importuj model LogEntry
import '../services/api_service.dart'; // Importuj ApiService
import '../models/food_item_create.dart';
import '../models/log_entry_create_frontend.dart'; // Importuj model LogEntryCreateFrontend

import 'auth_provider.dart'; // Importuj AuthProvider (ten Provider od niego zależy)

class FoodLogProvider with ChangeNotifier {
  // *** PRZECHOWUJ INSTANCJĘ ApiService PRZEKAZANĄ W KONSTRUKTORZE ***
  // Ta instancja jest singletonem zarządzanym przez Provider w main.dart.
  final ApiService _apiService; // Pole do przechowywania ApiService

  AuthProvider? _authProvider; // Przechowuje referencję do AuthProvider, dostarczoną przez ProxyProvider

  DailySummary? _dailySummary; // Przechowuje podsumowanie dzienne dla zalogowanego użytkownika
  List<FoodItem> _searchResults = []; // Przechowuje wyniki wyszukiwania produktów
  bool _isLoadingSummary = false; // Flaga ładowania podsumowania
  bool _isLoadingSearch = false; // Flaga ładowania wyników wyszukiwania
  bool _isLogging = false; // Flaga logowania nowego wpisu logu
  String? _error; // Przechowuje komunikat błędu dla tego Providera

  // Gettery udostępniające stan na zewnątrz
  DailySummary? get dailySummary => _dailySummary; // Pobierz podsumowanie
  List<FoodItem> get searchResults => _searchResults; // Pobierz wyniki wyszukiwania
  bool get isLoadingSummary => _isLoadingSummary; // Status ładowania podsumowania
  bool get isLoadingSearch => _isLoadingSearch; // Status ładowania wyszukiwania
  bool get isLogging => _isLogging; // Status logowania wpisu
  String? get error => _error; // Pobierz komunikat błędu

  // *** KONSTRUKTOR PRZYJMUJE INSTANCJĘ ApiService ***
  // Instancja ApiService jest wstrzykiwana z Providera w main.dart.
  FoodLogProvider(this._apiService);


  // Metoda wywoływana przez ProxyProvider w main.dart, gdy AuthProvider wywoła notifyListeners() (np. po checkLoginStatus, login, logout).
  // Jest to sposób na wstrzyknięcie (uzyskanie dostępu do) instancji AuthProvider.
  void updateAuth(AuthProvider auth) {
    // Sprawdź, czy referencja AuthProvider się zmieniła.
    if (_authProvider != auth) {
      _authProvider = auth;
      if (kDebugMode) {
        print("FoodLogProvider: AuthProvider reference updated.");
      }
    } // Logika poniżej reaguje na zmiany stanu w 'auth'.

    // *** KLUCZOWA LOGIKA AUTOMATYCZNEGO POBIERANIA PODSUMOWANIA PO ZALOGOWANIU ***
    // Warunki, kiedy powinniśmy próbować pobrać podsumowanie:
    // 1. Mamy referencję do AuthProvider (_authProvider nie jest null).
    // 2. AuthProvider zakończył swój startowy proces sprawdzania stanu logowania (hasCompletedCheck).
    //    To jest kluczowe, aby poczekać na ustalenie stanu zalogowania przez AuthProvider (co obejmuje ładowanie tokena i pobieranie danych usera).
    // 3. AuthProvider wskazuje, że użytkownik jest ZALOGOWANY (_authProvider!.isLoggedIn).
    //    POLEGAMY TERAZ NA TYM. Zakładamy, że jeśli AuthProvider.isLoggedIn jest true,
    //    to ApiService ma ważny token dzięki procesowi w AuthProvider.
    // 4. FoodLogProvider jeszcze nie ma danych DailySummary (_dailySummary jest null).
    //    Chcemy pobrać podsumowanie tylko raz po ustaleniu stanu zalogowania (lub po zalogowaniu/rejestracji w tej sesji).
    //    LUB, jeśli stan AuthProvider wskazuje, że jesteśmy zalogowani i zmienił się userId (np. przelogowanie).
    //    Ta druga logika wymagałaby przechowywania ostatniego userId w FoodLogProvider. Na razie skupiamy się na _dailySummary == null.
    // 5. Nie jesteśmy już w trakcie ładowania podsumowania (_isLoadingSummary jest false).
    if (_authProvider != null &&
        _authProvider!.hasCompletedCheck && // <-- SPRAWDŹ FLAGĘ ZAKOŃCZENIA SPRAWDZANIA Z AuthProvider
        _authProvider!.isLoggedIn && // <-- SPRAWDŹ STAN ZALOGOWANIA Z AuthProvider
        _dailySummary == null && // <-- Sprawdź, czy jeszcze nie mamy danych
        !_isLoadingSummary)
    {
      if (kDebugMode) {
        print("FoodLogProvider: Auth check completed & logged in & no summary, initiating fetching...");
      }
      // *** Wywołaj asynchronicznie pobieranie podsumowania! ***
      // Używamy .catchError() zamiast await, aby metoda updateAuth
      // mogła zakończyć swoje działanie natychmiast (ProxyProvider tego oczekuje od metody update).
      fetchDailySummary().catchError((e) {
        // Błędy pobierania są już obsługiwane w fetchDailySummary (ustawienie _error i notifyListeners).
        // Tutaj tylko logujemy, że błąd wystąpił asynchronicznie.
        if (kDebugMode) {
          print("FoodLogProvider: Error fetching summary during updateAuth (caught async): $e");
        }
      });

    } else if (_authProvider != null && _authProvider!.hasCompletedCheck && !_authProvider!.isLoggedIn && _dailySummary != null) {
      // *** KLUCZOWA LOGIKA: Wyczyść dane FoodLogProvider przy WYLOGOWANIU ***
      // Gdy AuthProvider zakończył sprawdzanie stanu (hasCompletedCheck) ORAZ wskazuje, że użytkownik jest WYLOGOWANY (isLoggedIn false)
      // ORAZ FoodLogProvider MA jeszcze jakieś stare dane (_dailySummary nie jest null).
      if (kDebugMode) {
        print("FoodLogProvider: Auth check completed & logged out, clearing state...");
      }
      _dailySummary = null; // Wyczyść podsumowanie
      _searchResults = []; // Wyczyść wyniki wyszukiwania
      _error = null; // Wyczyść błąd
      // Powiadom słuchaczy o wyczyszczeniu danych.
      // AuthProvider wywoła notifyListeners() po logout, co triggeruje to updateAuth.
      notifyListeners();
    } else {
      // Logowanie diagnostyczne, kiedy updateAuth jest wywołane, ale nie prowadzi do fetchowania ani czyszczenia.
      if (kDebugMode) {
        print("FoodLogProvider: UpdateAuth triggered, but conditions for fetching/clearing not met.");
        print("  - Auth is not null: ${_authProvider != null}");
        print("  - Auth check completed: ${_authProvider?.hasCompletedCheck}");
        print("  - Auth logged in: ${_authProvider?.isLoggedIn}");
        print("  - DailySummary is null: ${_dailySummary == null}");
        print("  - Not loading summary: ${!_isLoadingSummary}");
      }
    }
  }


  // Metoda do pobierania podsumowania dziennego - WYMAGA autoryzacji
  // Jest wywoływana przez updateAuth lub z UI (np. przez RefreshIndicator).
  // POLEGA NA TYM, że AuthProvider już ustalił stan logowania i ApiService ma token.
  Future<void> fetchDailySummary() async {
    // Sprawdź stan zalogowania z AuthProvider (zakładamy, że to wystarczy, aby ApiService było gotowe).
    if (_authProvider == null || !_authProvider!.isLoggedIn) {
      if (kDebugMode) {
        print("FoodLogProvider: Cannot fetch summary: user not logged in.");
      }
      _error = "Użytkownik nie jest zalogowany.";
      _dailySummary = null;
      _isLoadingSummary = false;
      notifyListeners();
      return;
    }
    // Nie sprawdzamy już ApiService.isLoggedIn() tutaj jawnie.

    // Sprawdzenie, czy już nie jesteśmy w trakcie ładowania
    if (_isLoadingSummary) {
      if (kDebugMode) {
        print("FoodLogProvider: Already loading summary, ignoring fetch request.");
      }
      return;
    }

    _isLoadingSummary = true;
    _error = null;
    notifyListeners();

    try {
      if (kDebugMode) {
        print("FoodLogProvider: Fetching daily summary from API...");
      }
      // Wywołaj ApiService.getDailySummary() - ApiService zajmie się dodaniem tokena (który powinien mieć).
      _dailySummary = await _apiService.getDailySummary();

      if (kDebugMode) {
        print("FoodLogProvider: Summary fetched successfully.");
      }
      // _dailySummary jest ustawione.
      // notifyListeners() w finally.
    } catch (e) {
      _error = "Błąd pobierania podsumowania: ${e.toString().replaceFirst('Exception: ', '')}";
      if (kDebugMode) {
        print("FoodLogProvider: Error fetching summary: $_error");
      }
      _dailySummary = null;
      // Jeśli błąd to 401/403 (np. token wygasł między checkLoginStatus a fetchDailySummary),
      // ApiService już obsłużył usunięcie tokena. AuthProvider zauważy to
      // przy następnej interakcji lub odświeżeniu Providerów.
    } finally {
      _isLoadingSummary = false;
      notifyListeners();
    }
  }

  // Metoda do wyszukiwania produktów (GET /foods) - WYMAGA autoryzacji
  Future<void> searchFoods(String query) async {
    // Sprawdź stan zalogowania z AuthProvider.
    if (_authProvider == null || !_authProvider!.isLoggedIn) {
      if (kDebugMode) {
        print("FoodLogProvider: Cannot search foods: user not logged in.");
      }
      _error = "Użytkownik nie jest zalogowany lub sesja wygasła.";
      _searchResults = [];
      _isLoadingSearch = false;
      notifyListeners();
      return;
    }
    // Nie sprawdzamy już ApiService.isLoggedIn() tutaj jawnie.

    if (query.isEmpty) {
      _searchResults = [];
      _error = null;
      if (!_isLoadingSearch) {
        notifyListeners();
      }
      return;
    }

    if (_isLoadingSearch) {
      if (kDebugMode) {
        print("FoodLogProvider: Already loading search, ignoring request.");
      }
      return;
    }

    _isLoadingSearch = true;
    _error = null;
    notifyListeners();

    try {
      if (kDebugMode) {
        print("FoodLogProvider: Searching foods for query: '$query'");
      }
      // Wywołaj ApiService.searchFoodItems() - ApiService zajmie się tokenem.
      _searchResults = await _apiService.searchFoodItems(query);

      if (kDebugMode) {
        print("FoodLogProvider: Search successful, found ${_searchResults.length} items.");
      }
      // _searchResults jest ustawione.
      // notifyListeners() w finally.
    } catch (e) {
      _error = "Błąd wyszukiwania: ${e.toString().replaceFirst('Exception: ', '')}";
      if (kDebugMode) {
        print("FoodLogProvider: Error searching food: $_error");
      }
      _searchResults = [];
    } finally {
      _isLoadingSearch = false;
      notifyListeners();
    }
  }

  // Metoda do logowania posiłku/przekąski (POST /log) - WYMAGA autoryzacji
  Future<bool> logFoodItem({
    String? foodItemId,
    String? customFoodName,
    double? customCaloriesPer100g,
    required double grams,
  }) async {
    // Sprawdź stan zalogowania z AuthProvider.
    if (_authProvider == null || !_authProvider!.isLoggedIn) {
      if (kDebugMode) {
        print("FoodLogProvider: Cannot log food: user not logged in.");
      }
      _error = "Użytkownik nie jest zalogowany lub sesja wygasła.";
      _isLogging = false;
      notifyListeners();
      return false;
    }
    // Nie sprawdzamy już ApiService.isLoggedIn() tutaj jawnie.

    if (_isLogging) {
      if (kDebugMode) {
        print("FoodLogProvider: Already logging, ignoring request.");
      }
      return false;
    }

    // Walidacja po stronie frontendu
    if (foodItemId == null && (customFoodName == null || customFoodName.isEmpty || customCaloriesPer100g == null)) {
      _error = "Musisz podać produkt z listy lub nazwę i kalorie niestandardowej przekąski.";
      if (kDebugMode) {
        print("FoodLogProvider: Validation failed: Must provide foodItemId or custom details.");
      }
      _isLogging = false;
      notifyListeners();
      return false;
    }
    if (grams <= 0) {
      _error = "Waga musi być większa od zera.";
      if (kDebugMode) {
        print("FoodLogProvider: Validation failed: Grams must be positive.");
      }
      _isLogging = false;
      notifyListeners();
      return false;
    }
    if (foodItemId == null && customCaloriesPer100g != null && customCaloriesPer100g <= 0) {
      _error = "Kalorie niestandardowej przekąski muszą być większe od zera.";
      if (kDebugMode) {
        print("FoodLogProvider: Validation failed: Custom calories must be positive.");
      }
      _isLogging = false;
      notifyListeners();
      return false;
    }


    _isLogging = true;
    _error = null;
    notifyListeners();

    try {
      if (kDebugMode) {
        print("FoodLogProvider: Logging food item...");
      }
      final logData = LogEntryCreateFrontend(
        foodItemId: foodItemId,
        customFoodName: customFoodName,
        customCaloriesPer100g: customCaloriesPer100g,
        grams: grams,
      );

      // Wywołaj ApiService.logFood() - ApiService zajmie się tokenem.
      await _apiService.logFood(logData);

      if (kDebugMode) {
        print("FoodLogProvider: Food item logged successfully.");
      }
      // Odśwież podsumowanie po udanym logowaniu.
      await fetchDailySummary();

      _isLogging = false;
      notifyListeners();
      return true;

    } catch (e) {
      _error = "Błąd logowania: ${e.toString().replaceFirst('Exception: ', '')}";
      if (kDebugMode) {
        print("FoodLogProvider: Error logging food: $_error");
      }
      _isLogging = false;
      notifyListeners();
      return false;
    }
  }

  // Metoda do dodawania nowego produktu - WYMAGA autoryzacji
  Future<FoodItem?> addNewFoodItem({
    required String name,
    required double calories,
    double? protein,
    double? carbs,
    double? fat,
  }) async {
    // Sprawdź stan zalogowania z AuthProvider.
    if (_authProvider == null || !_authProvider!.isLoggedIn) {
      if (kDebugMode) {
        print("FoodLogProvider: Cannot add new food: user not logged in.");
      }
      _error = "Użytkownik nie jest zalogowany lub sesja wygasła.";
      notifyListeners();
      return null;
    }
    // Nie sprawdzamy już ApiService.isLoggedIn() tutaj jawnie.

    _error = null;
    try {
      if (kDebugMode) {
        print("FoodLogProvider: Adding new food item: '$name'");
      }
      final newFoodData = FoodItemCreate(
        name: name,
        caloriesPer100g: calories,
        proteinPer100g: protein,
        carbsPer100g: carbs,
        fatPer100g: fat,
      );
      // Wywołaj ApiService.addFoodItem() - ApiService zajmie się tokenem.
      final newFood = await _apiService.addFoodItem(newFoodData);

      if (kDebugMode) {
        print("FoodLogProvider: New food item added successfully: ${newFood.name}");
      }
      return newFood;

    } catch (e) {
      _error = "Błąd dodawania produktu: ${e.toString().replaceFirst('Exception: ', '')}";
      if (kDebugMode) {
        print("FoodLogProvider: Error adding new food: $_error");
      }
      notifyListeners();
      return null;
    }
  }

  @override
  String toString() {
    return 'FoodLogProvider(isLoadingSummary: $isLoadingSummary, dailySummary: $_dailySummary != null ? "Loaded" : "Null", error: $_error)';
  }
}