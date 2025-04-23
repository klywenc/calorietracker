// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart'; // Importuj inicjalizację lokalizacji
import 'package:flutter/foundation.dart'; // Dla kDebugMode

// Importuj Providerów i ApiService
import 'providers/auth_provider.dart';
import 'providers/food_log_provider.dart';
import 'services/api_service.dart';

// Importuj ekrany (upewnij się, że te pliki istnieją!)
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/add_food_screen.dart';
import 'screens/add_snack_screen.dart';
// import 'utils/helpers.dart'; // Importuj helpery, jeśli używasz ich w main.dart

Future<void> main() async { // main musi być async, bo initializeDateFormatting jest async
  WidgetsFlutterBinding.ensureInitialized(); // Potrzebne przed inicjalizacją async i użyciem SharedPreferences przez ApiService

  // *** ZAINICJALIZUJ DANE LOKALIZACJI dla pakietu intl ***
  // Jest to wymagane, jeśli używasz DateFormat z konkretną lokalizacją (np. 'pl_PL').
  try {
    await initializeDateFormatting('pl', null);
    // await initializeDateFormatting('en_US', null); // Zainicjalizuj inne, jeśli używasz
    if (kDebugMode) {
      print("Intl locale data initialized successfully for 'pl'.");
    }
  } catch (e) {
    if (kDebugMode) {
      print("Error initializing Intl locale data for 'pl': $e");
    }
    // Ten błąd zazwyczaj nie zatrzymuje aplikacji, ale formatowanie dat może być domyślne (en)
  }

  // *** STWÓRZ INSTANCJĘ ApiService RAZ (Singleton w kontekście aplikacji) ***
  // ApiService będzie zarządzało cyklem życia tokena w SharedPreferences.
  final apiService = ApiService();
  // NIE CZEKAMY TUTAJ JAWNIE NA ZAKOŃCZENIE _loadToken W KONSTRUKTORZE ApiService.
  // Provider AuthProvider jest odpowiedzialny za sprawdzenie stanu logowania
  // i poczekanie na gotowość ApiService (implicitnie przez oczekiwanie na ApiService.getCurrentUser).

  runApp(MyApp(apiService: apiService)); // Przekaż instancję ApiService do głównego widżetu aplikacji
}

class MyApp extends StatelessWidget {
  // Pole do przechowywania instancji ApiService
  final ApiService apiService;

  // Konstruktor przyjmujący instancję ApiService
  const MyApp({Key? key, required this.apiService}) : super(key: key);


  @override
  Widget build(BuildContext context) {
    // MultiProvider do zarządzania wieloma Providerami w aplikacji
    return MultiProvider(
      providers: [
        // *** UDOSTĘPNIJ INSTANCJĘ ApiService PRZEZ Provider ***
        // To pozwala innym Providerom (AuthProvider, FoodLogProvider) uzyskać dostęp do tej samej instancji ApiService.
        Provider<ApiService>(create: (_) => apiService), // Użyj przekazanej instancji ApiService

        // AuthProvider zarządza stanem zalogowania/użytkownika.
        // OTRZYMUJE instancję ApiService z Provider<ApiService>.
        // *** POPRAWKA: Przekaż ApiService do konstruktora AuthProvider ***
        ChangeNotifierProvider(create: (context) => AuthProvider(Provider.of<ApiService>(context, listen: false))),

        // FoodLogProvider zarządza danymi dziennymi i wyszukiwaniem.
        // OTRZYMUJE instancję ApiService z Provider<ApiService>.
        // ZALEŻY od AuthProvider (aby wiedzieć, kto jest zalogowany).
        ChangeNotifierProxyProvider<AuthProvider, FoodLogProvider>(
          // *** POPRAWKA: Przekaż ApiService do konstruktora FoodLogProvider w create ***
            create: (context) => FoodLogProvider(Provider.of<ApiService>(context, listen: false)),
            // Metoda update jest wywoływana przy pierwszej konfiguracji ProxyProvider (create)
            // i za każdym razem, gdy AuthProvider wywoła notifyListeners().
            update: (ctx, auth, previousFoodLog) {
              // Upewnij się, że previousFoodLog nie jest null przy pierwszym wywołaniu (powinien być po create)
              // Przekaż mu tę samą instancję ApiService, którą otrzymał w create.
              // *** POPRAWKA: Przekaż ApiService do konstruktora FoodLogProvider w fallbacku update ***
              final newFoodLog = previousFoodLog ?? FoodLogProvider(Provider.of<ApiService>(context, listen: false)); // Fallback na wypadek (powinno być poprzednia instancja)
              // Wywołaj metodę updateAuth w instancji FoodLogProvider, przekazując aktualny AuthProvider.
              // To w tej metodzie FoodLogProvider zdecyduje, czy pobrać dane (np. po zalogowaniu).
              newFoodLog.updateAuth(auth);
              // Zwróć zaktualizowaną instancję FoodLogProvider.
              return newFoodLog;
            }
        ),
        // Możesz dodać innych Providerów tutaj.
      ],
      child: MaterialApp(
        title: 'Licznik Kalorii', // Tytuł aplikacji
        theme: ThemeData( // Definicja motywu graficznego
            primarySwatch: Colors.green, // Główny kolor motywu
            visualDensity: VisualDensity.adaptivePlatformDensity, // Dostosowanie gęstości wizualnej
            // Konfiguracja colorScheme dla nowszych wersji Flutter
            colorScheme: ColorScheme.fromSwatch(
              primarySwatch: Colors.green, // Główny kolor swatch
            ).copyWith(
              secondary: Colors.amberAccent, // Przykładowy kolor secondary (zamiast accentColor)
            ),
            // Definicja stylu dla przycisków ElevatedButton dla spójności
            elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 30, vertical: 12), // Domyślny padding
                    textStyle: const TextStyle(fontSize: 16) // Domyślny styl tekstu
                )
            )
        ),
        // Użyj Consumera do dynamicznego wyboru ekranu startowego na podstawie stanu AuthProvider.
        home: Consumer<AuthProvider>(
          builder: (ctx, auth, _) {
            // Logowanie stanu AuthProvider przy każdej przebudowie
            if (kDebugMode) {
              print("AppState rebuild triggered. isLoggedIn: ${auth.isLoggedIn}, isLoading: ${auth.isLoading}, checkCompleted: ${auth.hasCompletedCheck}");
            }
            // Pokaż ekran ładowania, gdy AuthProvider sprawdza status logowania przy starcie (_checkLoginStatus)
            // lub wykonuje inną operację (login, register, logout).
            // Stan ładowania na początku jest true, dopóki _checkLoginStatus się nie zakończy.
            if (auth.isLoading) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            // Jeśli AuthProvider zakończył ładowanie (isLoading false) i użytkownik jest zalogowany (isLoggedIn true),
            // pokaż HomeScreen.
            // W przeciwnym razie (isLoading false i isLoggedIn false), pokaż AuthScreen.
            return auth.isLoggedIn ? const HomeScreen() : const AuthScreen();
          },
        ),
        // Definicja tras nazwanych dla łatwiejszej nawigacji (opcjonalnie, ale dobra praktyka)
        routes: {
          '/home': (ctx) => const HomeScreen(), // Trasa do ekranu głównego
          '/add-food': (ctx) => const AddFoodScreen(), // Trasa do dodawania z bazy
          '/add-snack': (ctx) => const AddSnackScreen(), // Trasa do dodawania niestandardowej przekąski
          '/auth': (ctx) => const AuthScreen(), // Trasa do ekranu autentykacji (login/register)
        },
        // Jeśli używasz tras nazwanych, upewnij się, że wszystkie możliwe ekrany docelowe są tutaj zdefiniowane.
        // Możesz też zdefiniować onGenerateRoute dla bardziej zaawansowanej nawigacji.
      ),
    );
  }
}