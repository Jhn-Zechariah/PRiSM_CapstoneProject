import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/features/auth/data/firebase_auth_repo.dart';
import 'package:prism_app/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:prism_app/firebase_options.dart';
import 'package:prism_app/screens/splash_screen.dart';
import 'package:prism_app/themes/app_theme.dart';

import 'features/auth/data/firestore_profile_repo.dart';
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

  void toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
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
      ],
      //app
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        // Use the extracted themes here
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: _themeMode,
        /*
        Bloc consumer - Auth
         */
        home: SplashScreen(onThemeToggle: toggleTheme)
      )
    );

  }
}