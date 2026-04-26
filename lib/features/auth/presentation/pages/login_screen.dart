import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:prism_app/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:prism_app/features/auth/presentation/components/custom_textfield.dart';
import 'package:prism_app/features/auth/presentation/components/custom_button.dart';

import '../components/social_logins.dart';

class LoginScreen extends StatefulWidget {
  final void Function()? togglePages;
  final VoidCallback onThemeToggle;

  const LoginScreen({super.key, this.togglePages, required this.onThemeToggle});

  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _obscurePassword = true;

  //auth cubit
  late final authCubit = context.read<AuthCubit>();

  //login button press
  void _login() {
    //prepare email & pass
    final String email = emailController.text;
    final String password = passwordController.text;

    //validate fields
    if (_formKey.currentState!.validate()) {
      debugPrint("Email: ${emailController.text}");
      debugPrint("Password: ${passwordController.text}");

      //log in
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
          prefixIcon: Icons.email_outlined,
        ),
        actions: [
          //cancel
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              emailController.clear();
            },
            child: const Text("Cancel"),
          ),

          //reset
          TextButton(
            onPressed: () async {
              String message = await authCubit.forgotPassword(
                emailController.text,
              );

              if (!context.mounted) return;

              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(message)));
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
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const SizedBox(height: 60),
                  SvgPicture.asset(
                    isDarkMode
                        ? 'assets/logo_dark.svg'
                        : 'assets/logo_light.svg',
                    width: 200,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.business,
                      size: 80,
                      color: isDarkMode ? Colors.white24 : Colors.grey,
                    ),
                  ),
                  Text(
                    "Welcome Back!",
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : Colors.black,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account?",
                        style: TextStyle(
                          fontSize: 14,
                          color: isDarkMode ? Colors.white70 : Colors.black54,
                        ),
                      ),
                      GestureDetector(
                        onTap: widget.togglePages ?? () {},
                        child: Text(
                          " Sign Up",
                          style: TextStyle(fontSize: 14, color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  //Email
                  CustomTextField(
                    controller: emailController,
                    labelText: "Email",
                    prefixIcon: Icons.email_outlined,
                    validator: (value) => value == null || value.isEmpty
                        ? "Please enter your email"
                        : null,
                  ),

                  const SizedBox(height: fieldSpacing),

                  //Password
                  CustomTextField(
                    controller: passwordController,
                    labelText: "Password",
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

                  //forgot password
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

                  const SizedBox(height: fieldSpacing),

                  // Sign in button
                  CustomButton(
                    text: "Sign In",
                    onPressed: _login,
                  ),

                  const SizedBox(height: fieldSpacing),

                  Row(
                    children: [
                      Expanded(
                        child: Divider(
                          thickness: 1,
                          color: isDarkMode ? Colors.white10 : Colors.grey[300],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text(
                          "or sign in with",
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ),
                      Expanded(
                        child: Divider(
                          thickness: 1,
                          color: isDarkMode ? Colors.white10 : Colors.grey[300],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SocialLoginButton(
                        asset: 'assets/google.svg',
                        label: "Google",
                        isDarkMode: isDarkMode,
                        onTap: () async {
                          //Google Sign-In function here
                          authCubit.googleSignIn();
                        },
                      ),
                      const SizedBox(width: 20),
                      SocialLoginButton(
                        asset: 'assets/facebook.svg',
                        label: "Facebook",
                        isDarkMode: isDarkMode,
                        onTap: () {
                          //Facebook Sign-In logic here
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
