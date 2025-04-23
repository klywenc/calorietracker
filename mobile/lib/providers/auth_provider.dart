// lib/providers/auth_provider.dart
import 'package:flutter/foundation.dart'; // Dla kDebugMode
import 'package:shared_preferences/shared_preferences.dart'; // Wymagane przez ApiService (Api Service go używa)
import '../models/user.dart'; // Importuj model UserPublic
import '../services/api_service.dart'; // Importuj ApiService

class AuthProvider with ChangeNotifier {
  // *** PRZECHOWUJ INSTANCJĘ ApiService PRZEKAZANĄ W KONSTRUKTORZE ***
  // Ta instancja jest singletonem zarządzanym przez Provider w main.dart.
  final ApiService _apiService; // Pole do przechowywania ApiService

  UserPublic? _user; // Przechowuje pełne dane zalogowanego użytkownika
  bool _isLoading = false; // Flaga wskazująca, czy Provider wykonuje operację asynchroniczną (np. login, check status)
  String? _error; // Przechowuje komunikat błędu

  // *** NOWA FLAGA: Czy proces sprawdzania statusu logowania przy starcie został zakończony ***
  // Ta flaga pomaga innym Providerom (np. FoodLogProvider) wiedzieć, kiedy stan logowania jest ustalony.
  bool _hasCompletedCheck = false;

  // Gettery udostępniające stan na zewnątrz
  UserPublic? get user => _user; // Pobierz dane użytkownika
  bool get isLoggedIn => _user != null; // Status zalogowania (czy mamy dane użytkownika)
  bool get isLoading => _isLoading; // Status ładowania
  String? get error => _error; // Pobierz komunikat błędu
  String? get userId => _user?.id; // Bezpieczne pobieranie ID użytkownika (jeśli _user nie jest null)

  // *** NOWY GETTER dla flagi zakończenia sprawdzania statusu ***
  bool get hasCompletedCheck => _hasCompletedCheck; // Czy sprawdzanie statusu przy starcie zostało zakończone?

  // *** KONSTRUKTOR PRZYJMUJE INSTANCJĘ ApiService ***
  // Instancja ApiService jest wstrzykiwana z Providera w main.dart.
  AuthProvider(this._apiService) {
    if (kDebugMode) {
      print("AuthProvider: Instance created with ApiService. Starting checkLoginStatus...");
    }
    // Wywołaj asynchroniczną metodę sprawdzającą status logowania w tle przy tworzeniu Providera.
    // Nie czekamy na jej zakończenie tutaj, aby nie blokować UI.
    _checkLoginStatus();
  }

  // Metoda asynchroniczna do sprawdzania statusu logowania (na podstawie tokena w ApiService)
  // Jest wywoływana raz przy starcie aplikacji.
  Future<void> _checkLoginStatus() async {
    _isLoading = true; // Rozpocznij ładowanie
    _error = null; // Wyczyść poprzedni błąd
    _hasCompletedCheck = false; // Upewnij się, że flaga jest false na początku procesu
    notifyListeners(); // Powiadom słuchaczy o stanie ładowania (isLoading = true, hasCompletedCheck = false)

    try {
      // ApiService wczytuje token w tle w swoim konstruktorze (_loadToken), co jest asynchroniczne.
      // Zamiast sprawdzać ApiService.isLoggedIn() tutaj, po prostu SPRÓBUJEMY pobrać dane użytkownika z API.
      // ApiService.getCurrentUser() wewnętrznie sprawdzi, czy ma token i rzuci wyjątek (np. "No token available", 401/403), jeśli nie jest gotowy lub token jest nieprawidłowy.
      if (kDebugMode) {
        print("AuthProvider: Attempting to fetch user data from API using ApiService.getCurrentUser...");
      }
      // *** SPRÓBUJ POBRAĆ DANE UŻYTKOWNIKA ***
      // Ta operacja wymaga, aby ApiService miało załadowany token (lub próbowało go użyć).
      // Oczekujemy na zakończenie tej operacji.
      _user = await _apiService.getCurrentUser();

      // Jeśli powyższa linijka nie rzuciła wyjątku, pobrano dane i _user jest ustawiony.
      if (kDebugMode) {
        print("AuthProvider: ApiService.getCurrentUser successful. User data fetched: ${_user?.username}. Login status: Logged In.");
      }
      // notifyListeners() w finally.

    } catch (e) {
      // Jeśli ApiService.getCurrentUser() rzuci błąd (np. "No token available", "Authorization Error 401/403", błąd sieci), łapiemy go tutaj.
      // Oznacza to, że użytkownik nie jest (lub przestał być) zalogowany.
      // ApiService już usunął token w przypadku 401/403.
      if (kDebugMode) {
        print("AuthProvider: Error during checkLoginStatus: $e. Setting status to Not Logged In.");
      }
      _error = "Wystąpił błąd podczas wczytywania sesji. Zaloguj się ponownie: ${e.toString().replaceFirst('Exception: ', '')}"; // Ustaw komunikat błędu
      _user = null; // Upewnij się, że _user jest null po błędzie
    } finally {
      _isLoading = false; // Zakończ ładowanie
      _hasCompletedCheck = true; // *** Ustaw flagę na true po zakończeniu całego procesu sprawdzania statusu (sukces lub błąd) ***
      notifyListeners(); // POWIADOM WSZYSTKICH SŁUCHACZY o finalnym stanie (isLoading, isLoggedIn, _user, error, hasCompletedCheck)
      // To wywołanie powiadamia ProxyProvider w main.dart, co prowadzi do wywołania updateAuth w FoodLogProvider.
    }
  }


  // Metoda logowania użytkownika - wywoływana z UI
  Future<bool> login(String username, String password) async {
    _isLoading = true; // Rozpocznij ładowanie
    _error = null; // Wyczyść poprzedni błąd
    _hasCompletedCheck = false; // Resetuj flagę, bo rozpoczynamy nową operację autentykacji/loginu
    notifyListeners(); // Powiadom o stanie ładowania

    try {
      if (kDebugMode) {
        print("AuthProvider: Attempting to log in via API...");
      }
      // 1. Wywołaj login w ApiService. To wysyła dane do /token, pobiera token JWT i zapisuje go w SharedPreferences.
      // Metoda ApiService.login() zwraca Future<void>. Rzuci wyjątek w przypadku błędu (np. błędne dane logowania, błąd API).
      await _apiService.login(username, password);
      if (kDebugMode) {
        print("AuthProvider: ApiService.login successful (token obtained).");
      }

      // 2. Po pomyślnym pobraniu tokena, pobierz pełne dane użytkownika za pomocą nowego tokena.
      // Metoda ApiService.getCurrentUser() wysyła żądanie do /users/me/ z tokenem i zwraca Future<UserPublic>.
      // Ta operacja wymaga, aby ApiService miało załadowany token, co powinno być spełnione po pomyślnym ApiService.login().
      _user = await _apiService.getCurrentUser();

      if (kDebugMode) {
        print("AuthProvider: ApiService.getCurrentUser successful (user data obtained). Login successful.");
      }

      // Jeśli doszliśmy tutaj, oba kroki (pobranie tokena i pobranie danych użytkownika) się powiodły.
      // _user jest ustawiony, a getter isLoggedIn zwróci true.
      _isLoading = false; // Zakończ ładowanie
      _hasCompletedCheck = true; // *** Ustaw flagę na true po zakończeniu procesu logowania (sukces) ***
      notifyListeners(); // Powiadom wszystkich słuchaczy o udanym zalogowaniu (isLoading = false, _user = dane, isLoggedIn = true, hasCompletedCheck = true)
      // To wywołanie powiadomi ProxyProvider, co prowadzi do wywołania updateAuth w FoodLogProvider.
      return true; // Zalogowanie pomyślne

    } catch (e) {
      // Jeśli ApiService.login() lub ApiService.getCurrentUser() rzuci wyjątek, łapiemy go tutaj.
      // ApiService.login() obsłuży błędy takie jak błędne dane logowania.
      // ApiService.getCurrentUser() obsłuży błędy autoryzacji (np. token wygasł) i usunie token.
      _error = e.toString().replaceFirst('Exception: ', ''); // Ustaw czytelniejszy komunikat błędu
      if (kDebugMode) {
        print("AuthProvider: Login failed: $_error");
      }
      _isLoading = false; // Zakończ ładowanie
      _user = null; // Upewnij się, że _user jest null po błędzie logowania
      _hasCompletedCheck = true; // *** Ustaw flagę na true po zakończeniu procesu logowania (błąd) ***
      // ApiService już usunął token, jeśli błąd dotyczył autoryzacji.
      notifyListeners(); // Powiadom o błędzie (isLoading = false, _user = null, error = komunikat, hasCompletedCheck = true)
      return false; // Zalogowanie niepomyślne
    }
  }

  // Metoda rejestracji użytkownika - wywoływana z UI
  Future<bool> register(String username, String password, {String? email, int? goal}) async {
    _isLoading = true; // Rozpocznij ładowanie
    _error = null; // Wyczyść poprzedni błąd
    _hasCompletedCheck = false; // Resetuj flagę, bo rozpoczynamy nową operację
    notifyListeners(); // Powiadom o stanie ładowania

    try {
      if (kDebugMode) {
        print("AuthProvider: Attempting to register user...");
      }
      // 1. Wywołaj rejestrację w ApiService.
      await _apiService.register(username, password, email: email, goal: goal);
      if (kDebugMode) {
        print("AuthProvider: ApiService.register successful.");
      }

      // 2. Po pomyślnej rejestracji, automatycznie zaloguj użytkownika, aby od razu uzyskał token.
      if (kDebugMode) {
        print("AuthProvider: Registration successful, attempting auto-login...");
      }
      // *** Wywołaj metodę login tego Providera! ***
      // Metoda login wewnętrznie już pobiera token i dane użytkownika po uzyskaniu tokena
      // oraz ustawia flagi isLoading, _user, _error, hasCompletedCheck i wywołuje notifyListeners().
      // Czekamy na zakończenie całego procesu logowania.
      await login(username, password);

      // Jeśli doszliśmy tutaj, rejestracja i auto-login się powiodły (metoda login zwróciła true).
      return true; // Rejestracja i auto-login pomyślne

    } catch (e) {
      // Jeśli ApiService.register() lub wywołana metoda login() rzuci wyjątek, łapiemy go tutaj.
      _error = e.toString().replaceFirst('Exception: ', ''); // Ustaw komunikat błędu
      if (kDebugMode) {
        print("AuthProvider: Registration failed (during registration or auto-login): $_error");
      }
      // Stan isLoading, _user, hasCompletedCheck i error zostały już ustawione przez wywołaną metodę login().
      // W przypadku błędu *tylko* register, trzeba by ustawić flagi ręcznie:
      // _isLoading = false;
      // _user = null;
      // _hasCompletedCheck = true;
      // notifyListeners();
      return false; // Rejestracja niepomyślna
    }
  }

  // Metoda wylogowania użytkownika - wywoływana z UI
  Future<void> logout() async {
    _isLoading = true; // Pokaż, że trwa wylogowywanie (opcjonalne)
    _error = null; // Wyczyść błąd
    _hasCompletedCheck = false; // Resetuj flagę, bo stan logowania się zmienia na 'niezalogowany'
    notifyListeners(); // Powiadom o stanie ładowania (opcjonalne)

    try {
      if (kDebugMode) {
        print("AuthProvider: Attempting to log out...");
      }
      // Usuń token z SharedPreferences za pomocą ApiService.
      await _apiService.deleteToken();
      if (kDebugMode) {
        print("AuthProvider: ApiService.deleteToken successful.");
      }
    } catch (e) {
      // Błąd podczas usuwania tokena jest mało prawdopodobny, ale możliwy.
      if (kDebugMode) {
        print("AuthProvider: Error during token deletion: $e");
      }
      _error = "Błąd podczas usuwania sesji: ${e.toString().replaceFirst('Exception: ', '')}";
      // Mimo błędu przy usuwaniu tokena, stan lokalny i tak czyścimy.
    } finally {
      _user = null; // Wyczyść dane użytkownika lokalnie (_user = null, isLoggedIn = false)
      _isLoading = false; // Zakończ ładowanie
      _hasCompletedCheck = true; // *** Ustaw flagę na true po zakończeniu procesu wylogowania ***
      // ApiService.isLoggedIn() teraz zwróci false.
      notifyListeners(); // POWIADOM WSZYSTKICH SŁUCHACZY o finalnym stanie (isLoading = false, _user = null, isLoggedIn = false, hasCompletedCheck = true)
      // To wywołanie powiadomi ProxyProvider, co prowadzi do wywołania updateAuth w FoodLogProvider,
      // który powinien wyczyścić swoje dane dzienne.
      if (kDebugMode) {
        print("AuthProvider: Logout complete.");
      }
    }
  }
}