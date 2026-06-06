import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/features/auth/presentation/pages/login_screen.dart';
import 'package:prism_app/features/auth/presentation/pages/signup_screen.dart';
import '../../../../core/widgets/bottom_nav_and_drawer.dart';
import '../../../../core/widgets/loading.dart';
import '../cubits/auth_cubit.dart';
import '../cubits/auth_states.dart';

class AuthPage extends StatefulWidget {
  final Function(ThemeMode) onThemeToggle;
  const AuthPage({super.key, required this.onThemeToggle});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool showLoginPage = true;

  void togglePages() {
    setState(() {
      showLoginPage = !showLoginPage;
    });
  }

  @override
  Widget build(BuildContext context) {

    return BlocConsumer<AuthCubit, AuthState>(
      listener: (context, state) {
        if (state is Authenticated) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => AppNav(onThemeToggle: widget.onThemeToggle),
            ),
          );
        }
        else if (state is AuthError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      builder: (context, state) {
        if (state is AuthLoading) {
          return const LoadingScreen();
        }

        // Default: Show login or signup page
        if (showLoginPage) {
          return LoginScreen(
            // 🔹 FIXED: Wrapped in an anonymous function to defer execution until clicked
            onThemeToggle: () => widget.onThemeToggle,
            togglePages: togglePages,
          );
        } else {
          return SignupScreen(
            // 🔹 FIXED: Wrapped in an anonymous function to defer execution until clicked
            onThemeToggle: () => widget.onThemeToggle,
            togglePages: togglePages,
          );
        }
      },
    );
  }
}