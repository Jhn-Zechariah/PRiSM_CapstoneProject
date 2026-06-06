import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 🔹 Imported shared_preferences

import 'package:prism_app/features/auth/data/firebase_auth_repo.dart';
import 'package:prism_app/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:prism_app/firebase_options.dart';
import 'package:prism_app/core/widgets/splash_screen.dart';
import 'package:prism_app/core/theme/app_theme.dart';
import 'features/feeding/data/firestore_feeding_record_repo.dart';
import 'features/feeding/presentation/cubits/feeding_record_cubit.dart';
import 'features/medication/data/firestore_medicine_repo.dart';
import 'features/medication/presentation/cubits/medicine_cubit.dart';
import 'features/pig_management/data/firestore_pig_repo.dart';
import 'features/auth/data/firestore_profile_repo.dart';
import 'features/pig_management/presentation/cubits/pig_cubit.dart';
import 'features/auth/presentation/cubits/profile_cubit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 🔹 1. Load the saved theme mode BEFORE the app runs
  final prefs = await SharedPreferences.getInstance();
  final savedThemeIndex = prefs.getInt('theme_mode') ?? 0; // Default to 0 (System)
  final initialThemeMode = ThemeMode.values[savedThemeIndex];

  // 🔹 2. Pass the saved theme into MyApp
  runApp(MyApp(initialTheme: initialThemeMode));
}

class MyApp extends StatefulWidget {
  final ThemeMode initialTheme; // 🔹 Added to receive the loaded theme

  const MyApp({super.key, required this.initialTheme});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late ThemeMode _themeMode; // 🔹 Changed to late so we can set it in initState

  //auth repo
  final firebaseAuthRepo = FirebaseAuthRepo();

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialTheme; // 🔹 Apply the saved theme immediately
  }

  // 🔹 3. Replaced toggleTheme with updateTheme to handle ThemeMode and saving
  Future<void> updateTheme(ThemeMode newMode) async {
    setState(() {
      _themeMode = newMode;
    });

    // Save the user's choice so it remembers for next time
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', newMode.index);
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthCubit>(
          create: (context) => AuthCubit(authRepo: firebaseAuthRepo)..checkAuth(),
        ),
        BlocProvider<ProfileCubit>(
          create: (context) => ProfileCubit(profileRepo: FirebaseProfileRepo()),
        ),
        BlocProvider(
          create: (context) => PigCubit(pigRepo: FirebasePigRepo()),
        ),
        BlocProvider<FeedingRecordCubit>(
          create: (context) => FeedingRecordCubit(feedingRepo: FirestoreFeedingRecordRepo()),
        ),
        BlocProvider<MedicineCubit>(
          create: (context) => MedicineCubit(repository: FirestoreMedicineRepo()),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: _themeMode,

        // 🔹 4. Pass the new updateTheme function down to SplashScreen
        // (Make sure your SplashScreen constructor is updated to accept Function(ThemeMode)!)
        home: SplashScreen(onThemeToggle: updateTheme),
      ),
    );
  }
}