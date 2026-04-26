import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:prism_app/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:prism_app/features/auth/presentation/components/custom_textfield.dart';
import 'package:prism_app/features/auth/presentation/components/custom_button.dart';

import '../components/social_logins.dart';

class SignupScreen extends StatefulWidget {
  final void Function()? togglePages;
  final VoidCallback onThemeToggle;

  const SignupScreen({
    super.key,
    required this.togglePages,
    required this.onThemeToggle,
  });

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  //auth cubit
  late final authCubit = context.read<AuthCubit>();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  //sign uo botton pressed
  void _signup() {
    //prepare info
    final String username = usernameController.text;
    final String email = emailController.text;
    final String password = passwordController.text;

    if (_formKey.currentState!.validate()) {
      debugPrint("Username: ${usernameController.text}");
      debugPrint("Email: ${emailController.text}");
      debugPrint("Password: ${passwordController.text}");
      debugPrint("Confirm Password: ${confirmPasswordController.text}");

      authCubit.register(username, email, password);
    }
  }

  @override
  void dispose() {
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
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

                  // Dynamically swap the logo
                  SvgPicture.asset(
                    isDarkMode
                        ? 'assets/logo_dark.svg'
                        : 'assets/logo_light.svg',
                    width: 200,
                  ),

                  // Welcome text
                  Text(
                    "Let's Get You Started!",
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : Colors.black,
                    ),
                  ),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Already have an account?",
                        style: TextStyle(
                          fontSize: 14,
                          color: isDarkMode ? Colors.white70 : Colors.black54,
                        ),
                      ),
                      GestureDetector(
                        onTap: widget.togglePages,
                        child: Text(
                          " Log in",
                          style: TextStyle(fontSize: 14, color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Username Field
                  CustomTextField(
                    controller: usernameController,
                    labelText: "Username",
                    prefixIcon: Icons.account_circle_outlined,
                    validator: (value) => value == null || value.isEmpty
                        ? "Please enter your username"
                        : null,
                  ),
                  const SizedBox(height: fieldSpacing),

                  // Email Field
                  CustomTextField(
                    controller: emailController,
                    labelText: "Email",
                    prefixIcon: Icons.email_outlined,
                    validator: (value) => value == null || value.isEmpty
                        ? "Please enter your email"
                        : null,
                  ),
                  const SizedBox(height: fieldSpacing),

                  // Password Field
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
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? "Please enter your password"
                        : null,
                  ),
                  const SizedBox(height: fieldSpacing),

                  // Confirm Password Field
                  CustomTextField(
                    controller: confirmPasswordController,
                    labelText: "Confirm Password",
                    prefixIcon: Icons.lock_outlined,
                    obscureText: _obscureConfirmPassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: isDarkMode ? Colors.white60 : Colors.black54,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return "Please confirm your password";
                      if (value != passwordController.text) return "Passwords do not match";
                      return null;
                    },
                  ),
                  const SizedBox(height: fieldSpacing),

                  // Signup Button
                  CustomButton(
                    text: "Sign Up",
                    onPressed: _signup,
                  ),

                  const SizedBox(height: fieldSpacing),

                  // or sign up with separator
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
                          "or sign up with",
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

                  // Social login buttons row
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
