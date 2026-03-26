import 'package:flutter/material.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;
  const SignupScreen({super.key, required this.onThemeToggle});

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

      // After signup, take them back to Login
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              LoginScreen(onThemeToggle: widget.onThemeToggle),
        ),
      );
    }
  }

  static const double fieldSpacing = 20.0;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
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
                      TextButton(
                        onPressed: () {
                          // UPDATED: Pass the toggle function back to LoginScreen
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => LoginScreen(
                                onThemeToggle: widget.onThemeToggle,
                              ),
                            ),
                          );
                        },
                        child: const Text(
                          "Log in",
                          style: TextStyle(fontSize: 14, color: Colors.blue),
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
                      border: const OutlineInputBorder(
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
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(30)),
                      ),
                    ),
                    validator: (value) {
                      if (value!.isEmpty) return "Please confirm your password";
                      if (value != passwordController.text)
                        return "Passwords do not match";
                      return null;
                    },
                  ),
                  const SizedBox(height: fieldSpacing),

                  // Signup button
                  ElevatedButton(
                    onPressed: _signup,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: isDarkMode ? Colors.white : Colors.blue,
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

                  // or sign up with separator
                  const Row(
                    children: [
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
                      _buildSocialTile(
                        'assets/google.png',
                        "Google",
                        isDarkMode,
                      ),
                      const SizedBox(width: 20),
                      _buildSocialTile(
                        'assets/facebook.png',
                        "Facebook",
                        isDarkMode,
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

  // Helper method for social tiles to keep build method clean
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
