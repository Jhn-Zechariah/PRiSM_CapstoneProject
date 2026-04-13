import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:prism_app/features/auth/presentation/components/custom_textfield.dart';
import 'package:prism_app/features/auth/presentation/components/custom_button.dart';


class LoginScreen extends StatefulWidget {
  final void Function()? togglePages;
  final VoidCallback onThemeToggle;

  const LoginScreen({super.key, required this.togglePages,required this.onThemeToggle});

  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _obscurePassword = true;

  //login button press
  void _login() {
    //prepare email & pass
    final String email = emailController.text;
    final String password = passwordController.text;

    //auth cubit
    final authCubit = context.read<AuthCubit>();

    //validate fields
    if (_formKey.currentState!.validate()) {
      debugPrint("Email: ${emailController.text}");
      debugPrint("Password: ${passwordController.text}");

      //log in
      authCubit.login(email, password);
    }
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
                  Image.asset(
                    isDarkMode ? 'assets/logo_dark.png' : 'assets/logo_light.png',
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
                       onTap: widget.togglePages,
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
                    validator: (value) =>
                    value == null || value.isEmpty ? "Please enter your email" : null,
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
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: isDarkMode ? Colors.white60 : Colors.black54,
                      ),
                      onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                      ),
                    ),
                    validator: (value) =>
                    value == null || value.isEmpty ? "Please enter your password" : null,
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
                      _buildSocialTile('assets/google.png', "Google", isDarkMode),
                      const SizedBox(width: 20),
                      _buildSocialTile('assets/facebook.png', "Facebook", isDarkMode),
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

  Widget _buildSocialTile(String asset, String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
        borderRadius: BorderRadius.circular(20),
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            asset,
            width: 25,
            height: 25,
            errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.login, size: 25),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}