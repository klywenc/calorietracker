// lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'; // Dodany import

// Importuj modele z plików
import '../models/user.dart';
import '../models/food_item.dart';
import '../models/log_entry.dart';
import '../models/daily_summary.dart';
import '../models/food_item_create.dart';
import '../models/log_entry_create_frontend.dart'; // <-- Poprawny import


class ApiService {
  // !!! WAŻNE: ZMIEŃ NA ADRES SWOJEGO API !!!
  // Przykład dla emulatora Androida: "http://10.0.2.2:8000"
  // Przykład dla fizycznego urządzenia w tej samej sieci: "http://TWOJ_LOKALNY_IP_UBUNTU:8000"
  // Przykład dla ngrok: "https://TWOJ_ADRES_NGROK.ngrok.io"
  // Przykład dla wdrożonego API: "https://api.twojadomena.com"
  final String _baseUrl = "http://localhost:8000"; // <-- ZMIEŃ TUTAJ!

  String? _token;

  // Nie deklarujemy już klasy LogEntryCreateFrontend tutaj.
  // Jest ona zaimportowana z 'package:untitled/models/log_entry_create_frontend.dart'.

  ApiService() {
    // Uruchamiamy _loadToken w tle, nie czekamy na jego zakończenie w konstruktorze
    // To nie blokuje UI podczas startu, ale oznacza, że pierwsze wywołania
    // chronionych endpointów przed załadowaniem tokena mogą rzucić błąd "No token available".
    // Provider AuthProvider powinien to obsłużyć.
    _loadToken();
  }

  // Metoda do wczytywania tokena z SharedPreferences
  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('jwt_token');
    if (kDebugMode) {
      print("ApiService: Loaded token: $_token");
    }
    // WAŻNE: Ta metoda nie powinna wywoływać notifyListeners(),
    // bo ApiService nie jest ChangeNotifier. Za zarządzanie stanem UI
    // odpowiada AuthProvider, który wywołuje ApiService.isLoggedIn().
  }

  // Metoda do zapisywania tokena w SharedPreferences
  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);
    _token = token; // Aktualizujemy też lokalne pole
    if (kDebugMode) {
      print("ApiService: Token saved.");
    }
  }

  // Metoda do usuwania tokena z SharedPreferences (np. przy wylogowaniu)
  Future<void> deleteToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    _token = null; // Czyścimy lokalne pole
    if (kDebugMode) {
      print("ApiService: Token deleted.");
    }
  }

  // Funkcja pomocnicza do dodawania nagłówków autoryzacyjnych
  Map<String, String> _getAuthHeaders({String contentType = 'application/json'}) {
    final Map<String, String> headers = {
      'Content-Type': contentType,
    };
    // Dodaj nagłówek Authorization tylko jeśli token istnieje
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  // Funkcja pomocnicza do obsługi odpowiedzi API
  dynamic _handleResponse(http.Response response) {
    final decodedBody = jsonDecode(utf8.decode(response.bodyBytes)); // Użyj UTF-8

    if (kDebugMode) {
      print("ApiService: Response Status: ${response.statusCode}");
      print("ApiService: Response Body: $decodedBody");
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decodedBody;
    } else if (response.statusCode == 401 || response.statusCode == 403) {
      // W przypadku błędu autoryzacji, usuń token lokalnie
      deleteToken(); // Usuń token z SharedPreferences i lokalnego pola
      final String errorMessage = decodedBody is Map && decodedBody.containsKey('detail')
          ? decodedBody['detail'].toString()
          : response.reasonPhrase ?? 'Unauthorized / Forbidden';
      // Rzuć wyjątek, który Providerzy mogą złapać
      throw Exception('Authorization Error (${response.statusCode}): $errorMessage. Please log in again.');
    }
    else {
      // Spróbuj wyciągnąć 'detail' z odpowiedzi błędu FastAPI
      final String errorMessage = decodedBody is Map && decodedBody.containsKey('detail')
          ? decodedBody['detail'].toString()
          : response.reasonPhrase ?? 'Unknown API Error';
      throw Exception(
          'Failed API Call (${response.statusCode}): $errorMessage');
    }
  }

  // --- Metody API ---

  // Endpoint /register nie wymaga autoryzacji
  Future<UserPublic> register(String username, String password, {String? email, int? goal}) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/register'),
      // Nie używamy _getAuthHeaders(), bo register nie wymaga tokena
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'email': email,
        'daily_calorie_goal': goal,
      }),
    );
    final data = _handleResponse(response);
    return UserPublic.fromJson(data);
  }

  // Zmodyfikowana metoda login - teraz używa /token i zapisuje token
  // Zwraca Token, a nie UserPublic (jak poprzednio)
  Future<void> login(String username, String password) async {
    if (kDebugMode) {
      print("ApiService: Attempting login with username: '$username'");
    }
    // Użyj 'application/x-www-form-urlencoded' dla endpointu /token
    final response = await http.post(
      Uri.parse('$_baseUrl/token'),
      headers: _getAuthHeaders(contentType: 'application/x-www-form-urlencoded'), // Specjalny nagłówek
      body: {
        'username': username,
        'password': password,
      },
    );

    // Obsługa odpowiedzi - zwróci błąd jeśli status nie jest 2xx
    final data = _handleResponse(response);

    // Zapisz token po pomyślnym zalogowaniu
    if (data != null && data['access_token'] != null) {
      await _saveToken(data['access_token']);
    } else {
      // To raczej nie powinno się zdarzyć, jeśli _handleResponse nie rzuciło wyjątku
      throw Exception("ApiService: Login successful, but no token received from API.");
    }
  }

  // Metoda do pobierania danych zalogowanego użytkownika
  // WYMAGA autoryzacji (tokena)
  Future<UserPublic> getCurrentUser() async {
    // Sprawdź, czy token istnieje, zanim wykonasz zapytanie
    if (_token == null) {
      throw Exception("ApiService: No authentication token available for getCurrentUser. Please log in.");
    }
    final response = await http.get(
      Uri.parse('$_baseUrl/users/me/'),
      headers: _getAuthHeaders(), // Użyj nagłówków z tokenem
    );
    final data = _handleResponse(response);
    return UserPublic.fromJson(data);
  }

  // Metoda do pobierania danych użytkownika po ID (wymaga autoryzacji)
  Future<UserPublic> getUserById(String userId) async {
    if (_token == null) {
      throw Exception("ApiService: No authentication token available for getUserById. Please log in.");
    }
    final response = await http.get(
      Uri.parse('$_baseUrl/users/$userId'), // Endpoint po ID
      headers: _getAuthHeaders(),
    );
    final data = _handleResponse(response);
    return UserPublic.fromJson(data);
  }


  // Metoda wyszukiwania produktów
  // WYMAGA autoryzacji
  Future<List<FoodItem>> searchFoodItems(String query) async {
    if (_token == null) {
      throw Exception("ApiService: No authentication token available for searchFoodItems. Please log in.");
    }
    final response = await http.get(
      // Użyj .replace() do bezpiecznego dodania parametrów zapytania
      Uri.parse('$_baseUrl/foods').replace(queryParameters: {'search': query}),
      headers: _getAuthHeaders(), // Użyj nagłówków z tokenem
    );
    final data = _handleResponse(response) as List;
    return data.map((item) => FoodItem.fromJson(item)).toList();
  }

  // Metoda dodawania produktu
  // Przyjmuje obiekt FoodItemCreate
  // WYMAGA autoryzacji
  Future<FoodItem> addFoodItem(FoodItemCreate food) async {
    if (_token == null) {
      throw Exception("ApiService: No authentication token available for addFoodItem. Please log in.");
    }
    final response = await http.post(
      Uri.parse('$_baseUrl/foods'),
      headers: _getAuthHeaders(), // Użyj nagłówków z tokenem
      body: jsonEncode(food.toJson()), // Użyj toJson() z modelu FoodItemCreate
    );
    final data = _handleResponse(response);
    return FoodItem.fromJson(data);
  }

  // Metoda logowania posiłku
  // PRZYJMUJE obiekt LogEntryCreateFrontend
  // WYMAGA autoryzacji
  Future<LogEntry> logFood(LogEntryCreateFrontend logData) async { // <--- Przyjmuje obiekt LogEntryCreateFrontend
    if (_token == null) {
      throw Exception("ApiService: No authentication token available for logFood. Please log in.");
    }

    final response = await http.post(
      Uri.parse('$_baseUrl/log'),
      headers: _getAuthHeaders(),
      body: jsonEncode(logData.toJson()), // Użyj toJson() z obiektu LogEntryCreateFrontend
    );
    final data = _handleResponse(response);
    return LogEntry.fromJson(data);
  }

  // Metoda pobierania dziennego podsumowania
  // JUŻ NIE WYMAGA userId jako parametru, bo API pobiera go z tokena
  // WYMAGA autoryzacji
  Future<DailySummary> getDailySummary() async {
    if (_token == null) {
      throw Exception("ApiService: No authentication token available for getDailySummary. Please log in.");
    }
    // API pobiera ID użytkownika z tokena, nie potrzebujemy go w Query Parameters
    final response = await http.get(
      Uri.parse('$_baseUrl/log/summary/today'),
      headers: _getAuthHeaders(), // Użyj nagłówków z tokenem
    );
    final data = _handleResponse(response);
    return DailySummary.fromJson(data);
  }

  // Dodaj metodę do sprawdzenia, czy ApiService ma token
  bool isLoggedIn() {
    return _token != null;
  }
}