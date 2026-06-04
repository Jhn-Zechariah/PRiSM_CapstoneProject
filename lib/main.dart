import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/features/auth/data/firebase_auth_repo.dart';
import 'package:prism_app/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:prism_app/firebase_options.dart';
import 'package:prism_app/core/widgets/splash_screen.dart';
import 'package:prism_app/core/theme/app_theme.dart';
import 'features/feeding/data/firestore_feeding_record_repo.dart';
import 'features/feeding/presentation/cubits/feeding_record_cubit.dart';
import 'features/pig_management/data/firestore_pig_repo.dart';
import 'features/auth/data/firestore_profile_repo.dart';
import 'features/pig_management/presentation/cubits/pig_cubit.dart';
import 'features/auth/presentation/cubits/profile_cubit.dart';

void main() async {
  // firebase setup
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // run app
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.system;

  //auth repo
  final firebaseAuthRepo = FirebaseAuthRepo();

  // 🔹 FIXED: Modified to accept the current visual state of the UI
  // This explicitly sets the opposite theme mode and stops the 2-tap system delay bug.
  void toggleTheme(bool isCurrentDark) {
    setState(() {
      _themeMode = isCurrentDark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        //auth cubit
        BlocProvider<AuthCubit>(
          create: (context) => AuthCubit(authRepo: firebaseAuthRepo)..checkAuth(),
        ),
        BlocProvider<ProfileCubit>(
          create: (context) => ProfileCubit(profileRepo: FirebaseProfileRepo()),
        ),
        BlocProvider(
          // You provide the concrete Firebase version here
          create: (context) => PigCubit(pigRepo: FirebasePigRepo()),
        ),
        BlocProvider<FeedingRecordCubit>(
          create: (context) => FeedingRecordCubit(feedingRepo: FirestoreFeedingRecordRepo()),
        ),
      ],
      //app
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        // Use the extracted themes here
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: _themeMode,

        // 🔹 FIXED: The compiler is happy now that signatures match perfectly!
        home: SplashScreen(onThemeToggle: toggleTheme),
      ),
    );
  }
}