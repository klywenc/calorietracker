import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

enum AuthMode { login, register }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  AuthMode _authMode = AuthMode.login;
  final _passwordController = TextEditingController();
  String? _username, _password, _email;
  int? _dailyGoal = 2000; // Domyślny cel

  void _switchAuthMode() {
    setState(() {
      _authMode = _authMode == AuthMode.login ? AuthMode.register : AuthMode.login;
    });
    _formKey.currentState?.reset(); // Resetuj walidację po zmianie trybu
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return; // Nieprawidłowe dane
    }
    _formKey.currentState!.save(); // Zapisz wartości z pól

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    bool success = false;

    try {
      if (_authMode == AuthMode.login) {
        success = await authProvider.login(_username!, _password!);
      } else {
        success = await authProvider.register(
            _username!, _password!, email: _email, goal: _dailyGoal);
      }

      if (!success && mounted) {
        // Pokaż błąd z providera, jeśli logowanie/rejestracja się nie powiodły
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.error ?? 'Wystąpił nieznany błąd.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      // Jeśli sukces, provider sam zmieni stan i `main.dart` przełączy ekran
    } catch (error) {
      // Ogólny błąd (np. sieciowy)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Błąd: ${error.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = Provider.of<AuthProvider>(context).isLoading;

    return Scaffold(
      appBar: AppBar(
        title: Text(_authMode == AuthMode.login ? 'Logowanie' : 'Rejestracja'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                TextFormField(
                  decoration: InputDecoration(labelText: 'Nazwa użytkownika'),
                  keyboardType: TextInputType.text,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Podaj nazwę użytkownika';
                    }
                    return null;
                  },
                  onSaved: (value) => _username = value,
                ),
                if (_authMode == AuthMode.register)
                  TextFormField(
                    decoration: InputDecoration(labelText: 'Email (opcjonalnie)'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value != null && value.isNotEmpty && !value.contains('@')) {
                        return 'Podaj poprawny adres email';
                      }
                      return null;
                    },
                    onSaved: (value) => _email = value,
                  ),
                TextFormField(
                  decoration: InputDecoration(labelText: 'Hasło'),
                  obscureText: true,
                  controller: _passwordController,
                  validator: (value) {
                    if (value == null || value.length < 6) {
                      return 'Hasło musi mieć co najmniej 6 znaków';
                    }
                    return null;
                  },
                  onSaved: (value) => _password = value,
                ),
                if (_authMode == AuthMode.register)
                  TextFormField(
                    decoration: InputDecoration(labelText: 'Potwierdź hasło'),
                    obscureText: true,
                    validator: (value) {
                      if (value != _passwordController.text) {
                        return 'Hasła nie są zgodne';
                      }
                      return null;
                    },
                  ),
                if (_authMode == AuthMode.register)
                  TextFormField(
                    decoration: InputDecoration(labelText: 'Dzienny cel kalorii (opcjonalnie)'),
                    keyboardType: TextInputType.number,
                    initialValue: _dailyGoal.toString(), // Domyślna wartość
                    validator: (value) {
                      if (value != null && value.isNotEmpty) {
                        final number = int.tryParse(value);
                        if (number == null || number <= 0) {
                          return 'Podaj poprawną liczbę dodatnią';
                        }
                      }
                      return null;
                    },
                    onSaved: (value) {
                      if (value != null && value.isNotEmpty) {
                        _dailyGoal = int.tryParse(value);
                      } else {
                        _dailyGoal = null; // Ustaw null, jeśli puste
                      }
                    },
                  ),
                SizedBox(height: 20),
                if (isLoading)
                  CircularProgressIndicator()
                else
                  ElevatedButton(
                    onPressed: _submit,
                    child: Text(_authMode == AuthMode.login ? 'Zaloguj się' : 'Zarejestruj się'),
                  ),
                TextButton(
                  onPressed: _switchAuthMode,
                  child: Text(
                      '${_authMode == AuthMode.login ? 'Nie masz konta? Zarejestruj się' : 'Masz już konto? Zaloguj się'}'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}