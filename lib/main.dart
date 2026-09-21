import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Quran data is loaded by the Quran screens.
  // Do not block app startup on a Quran asset error.
  runApp(const TasbihApp());
}

class TasbihApp extends StatefulWidget {
  const TasbihApp({super.key});

  @override
  State<TasbihApp> createState() => _TasbihAppState();
}

class _TasbihAppState extends State<TasbihApp> {
  bool darkMode = false;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final savedDarkMode = await StorageService.getDarkMode();

    if (!mounted) return;

    setState(() {
      darkMode = savedDarkMode;
      isLoading = false;
    });
  }

  Future<void> changeTheme(bool value) async {
    setState(() {
      darkMode = value;
    });

    await StorageService.saveDarkMode(value);
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tasbih Counter',
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF087F5B),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF087F5B),
          brightness: Brightness.dark,
        ),
      ),
      home: HomeScreen(
        onThemeChanged: changeTheme,
        isDarkMode: darkMode,
      ),
    );
  }
}
