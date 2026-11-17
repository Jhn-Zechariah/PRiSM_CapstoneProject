import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:prism_app/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:prism_app/core/widgets/button.dart';

import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/snackbar.dart';
import '../../../../core/widgets/textfield.dart';

class LoginScreen extends StatefulWidget {
  final void Function()? togglePages;
  final Function(ThemeMode) onThemeToggle;

  const LoginScreen({super.key, this.togglePages, required this.onThemeToggle});

  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _obscurePassword = true;

  //auth cubits
  late final authCubit = context.read<AuthCubit>();

  //login button press
  void _login() {
    final String email = emailController.text.trim();
    final String password = passwordController.text;

    if (_formKey.currentState!.validate()) {
      authCubit.login(email, password);
    }
  }

  //forgot password
  void openForgotPasswordBox(String? email) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Forgot Password"),
        content: CustomTextField(
          controller: emailController,
          labelText: "Email",
          border: 10,
          prefixIcon: Icons.email_outlined,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              emailController.clear();
            },
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              final emailError = Validators.email(emailController.text);
              if (emailError != null) {
                CustomSnackbar.show(
                  context: context,
                  isError: true,
                  message: emailError,
                );
                return;
              }

              String message = await authCubit.forgotPassword(
                emailController.text.trim(),
              );

              if (!context.mounted) return;
              CustomSnackbar.show(
                context: context,
                isError: message.contains("error"),
                message: message,
              );

              Navigator.pop(context);
              emailController.clear();
            },
            child: const Text("Reset"),
          ),
        ],
      ),
    );
  }

  static const double fieldSpacing = 20.0;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF121212) : Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - 48).clamp(0.0, double.infinity),
              ),
              child: Center(
                child: SizedBox(
                  width: 440,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SvgPicture.asset(
                          isDarkMode
                              ? 'assets/logo_dark.svg'
                              : 'assets/logo_light.svg',
                          width: 120,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            Icons.business,
                            size: 80,
                            color: isDarkMode ? Colors.white24 : Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Welcome Back!",
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Sign in with your team-provided account",
                          style: TextStyle(
                            fontSize: 16,
                            color: isDarkMode ? Colors.white70 : Colors.black54,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 32),

                        // Email
                        CustomTextField(
                          controller: emailController,
                          labelText: "Email",
                          border: 10,
                          prefixIcon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validator: Validators.email,
                        ),

                        const SizedBox(height: fieldSpacing),

                        // Password
                        CustomTextField(
                          controller: passwordController,
                          labelText: "Password",
                          border: 10,
                          prefixIcon: Icons.lock_outlined,
                          obscureText: _obscurePassword,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: isDarkMode ? Colors.white60 : Colors.black54,
                            ),
                            onPressed: () =>
                                setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? "Please enter your password"
                              : null,
                        ),

                        const SizedBox(height: 10),

                        // Forgot password
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            GestureDetector(
                              onTap: () =>
                                  openForgotPasswordBox(emailController.text),
                              child: const Text(
                                "forgot password?",
                                style: TextStyle(fontSize: 14, color: Colors.blue),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Sign in button
                        CustomButton(
                          text: "Sign In",
                          borderColor: false,
                          onPressed: _login,
                          backgroundColor: Colors.blue,
                          color: Colors.white,
                        ),

                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? const Color(0xFF1B2635)
                                : const Color(0xFFF0F6FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 20,
                                color: isDarkMode
                                    ? Colors.blue.shade200
                                    : Colors.blue.shade700,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Accounts are provided by our team. Contact us if you need an account or help signing in.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.5,
                                    color: isDarkMode
                                        ? Colors.white70
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
