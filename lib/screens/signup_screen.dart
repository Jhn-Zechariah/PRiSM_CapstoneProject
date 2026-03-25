import 'package:flutter/material.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmpasswordController =
      TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  void _signup() {
    if (_formKey.currentState!.validate()) {
      debugPrint("Email: ${emailController.text}");
      debugPrint("Password: ${passwordController.text}");
      debugPrint("Confirm Password: ${confirmpasswordController.text}");
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
                    "Let's Get You Started!",
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
                        "Already have an account?",
                        style: TextStyle(
                          fontSize: 14,
                          color: isDarkMode ? Colors.white70 : Colors.black54,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          // Navigate to sign up screen
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => LoginScreen(),
                            ),
                          );
                        },
                        child: Text(
                          "Log in",
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
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: "Email",
                      prefixIcon: Icon(Icons.email_outlined),
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
                    controller: passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: "Password",
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(30)),
                      ),
                    ),
                    validator: (value) =>
                        value!.isEmpty ? "Please enter your password" : null,
                  ),
                  const SizedBox(height: fieldSpacing),

                  // Confirm Password field
                  TextFormField(
                    controller: confirmpasswordController,
                    obscureText: _obscureConfirmPassword,
                    decoration: InputDecoration(
                      labelText: "Confirm Password",
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(30)),
                      ),
                    ),
                    validator: (value) =>
                        value!.isEmpty ? "Please enter your password" : null,
                  ),
                  const SizedBox(height: fieldSpacing),

                  // Signup button
                  ElevatedButton(
                    onPressed: _signup,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: isDarkMode
                          ? const Color.fromARGB(255, 255, 255, 255)
                          : Colors.blue,
                      foregroundColor: isDarkMode ? Colors.black : Colors.white,
                    ),
                    child: const Text(
                      "Sign Up",
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
                          "or sign up with",
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ),
                      Expanded(
                        child: Divider(thickness: 1, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Social login buttons row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Google Button
                      GestureDetector(
                        onTap: () {
                          // Handle Google sign-in
                        },
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.white,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: Image.asset('assets/google.png'),
                            // Or use Image.network for a URL
                          ),
                        ),
                      ),

                      const SizedBox(width: 30),

                      // Facebook Button
                      GestureDetector(
                        onTap: () {
                          // Handle Facebook sign-in
                        },
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.white,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: Image.asset('assets/facebook.png'),
                          ),
                        ),
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
