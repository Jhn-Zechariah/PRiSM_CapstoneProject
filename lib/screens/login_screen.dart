// login_screen.dart
import 'package:flutter/material.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  void _login() {
    if (_formKey.currentState!.validate()) {
      debugPrint("Email: ${_emailController.text}");
      debugPrint("Password: ${_passwordController.text}");
    }
  }

  static const double fieldSpacing = 20.0;
  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // SafeArea prevents your UI from overlapping with the phone's status bar
      body: SafeArea(
        // SingleChildScrollView prevents keyboard overflow errors
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  // 1. ADD THIS TO PUSH EVERYTHING DOWN:
                  // Adjust the height number to move it up or down more
                  const SizedBox(height: 80),

                  // Dynamically swap the logo
                  Image.asset(
                    isDarkMode
                        ? 'assets/logo_dark.png'
                        : 'assets/logo_light.png',
                    width: 200,
                  ),

                  // Welcome text
                  Text(
                    "Welcome Back!",
                    style: TextStyle(
                      fontSize: 35,
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
                      TextButton(
                        onPressed: () {
                          // Navigate to sign up screen
                        },
                        child: Text(
                          "Sign Up",
                          style: TextStyle(
                            fontSize: 14,
                            color: isDarkMode ? Colors.blue : Colors.blue,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Email field
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: "Email",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(30)),
                      ),
                    ),
                    validator: (value) =>
                        value!.isEmpty ? "Please enter your email" : null,
                  ),
                  const SizedBox(height: fieldSpacing),

                  // Password field
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: "Password",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(30)),
                      ),
                    ),
                    validator: (value) =>
                        value!.isEmpty ? "Please enter your password" : null,
                  ),
                  const SizedBox(height: fieldSpacing),

                  // Login button
                  ElevatedButton(
                    onPressed: _login,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: isDarkMode
                          ? const Color.fromARGB(255, 255, 255, 255)
                          : Colors.blue,
                      foregroundColor: isDarkMode ? Colors.black : Colors.white,
                    ),
                    child: const Text(
                      "Sign In",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: fieldSpacing),

                  //or sign up with
                  Row(
                    children: const [
                      Expanded(
                        child: Divider(thickness: 1, color: Colors.grey),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text(
                          "or sign in with",
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ),
                      Expanded(
                        child: Divider(thickness: 1, color: Colors.grey),
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
