// Plik: lib/utils/helpers.dart
import 'package:intl/intl.dart';

// Prosty formater daty i czasu
String formatDateTime(DateTime dateTime) {
  // Przykład: 'HH:mm, dd MMM' -> '14:35, 25 paź'
  // Upewnij się, że lokalizacja 'pl_PL' jest wspierana przez Twoje urządzenie/emulator
  // lub dodaj flutter_localizations (zobacz niżej)
  try {
    // Używaj bezpośrednio lokalizacji
    return DateFormat('HH:mm, dd MMM', 'pl_PL').format(dateTime);
  } catch (e) {
    // Fallback na domyślny format, jeśli pl_PL zawiedzie
    print("Błąd formatowania daty dla pl_PL: $e. Używam formatu domyślnego.");
    return DateFormat('HH:mm, dd MMM').format(dateTime);
  }
}

/* USUŃ TĘ FUNKCJĘ:
// Inicjalizacja lokalizacji dla intl (wywołaj w main.dart)
Future<void> initializeDateFormattingForLocale() async {
  // TA LINIA POWODUJE BŁĄD W NOWSZYCH WERSJACH:
  // await DateFormat.initializeDateFormatting('pl_PL', null);
  // Zamiast tego polegamy na automatycznym ładowaniu lub flutter_localizations
  print("Inicjalizacja formatowania daty (usunięto jawną funkcję).");
}
*/