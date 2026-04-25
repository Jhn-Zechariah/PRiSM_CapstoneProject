import 'package:flutter/material.dart';
import 'package:prism_app/features/auth/presentation/components/app_top_bar.dart';
import 'package:prism_app/features/auth/presentation/components/custom_text.dart';
import 'package:prism_app/features/auth/presentation/components/custom_button.dart';
import 'package:prism_app/features/auth/presentation/components/custom_textfield.dart';
import 'package:firebase_auth/firebase_auth.dart';
// Note: If you renamed your button to EditMyProfileButton, import it here instead

class MyProfile extends StatefulWidget {
  const MyProfile({super.key});

  @override
  State<MyProfile> createState() => _MyProfileState();
}

class _MyProfileState extends State<MyProfile> {
  // 1. Logic State
  bool _isEditing = false;

  // 2. Controllers to manage the input data
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();

    final user = FirebaseAuth.instance.currentUser;

    _emailController.text = user?.email ?? "";
    _usernameController.text = user?.displayName ?? "";
  }

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // 3. Logic to toggle editing mode
  void _editProfile() {
    setState(() {
      _isEditing = !_isEditing;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTopBar(showBackButton: true, title: "My Profile"),
              const SizedBox(height: 24),

              // --- Profile Header ---
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: isDarkMode
                        ? Colors.white10
                        : Colors.black12,
                    child: Icon(
                      Icons.person_outline,
                      color: isDarkMode ? Colors.white : Colors.black87,
                      size: 45,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CustomText(
                        type: TextType.username,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      const CustomText(type: TextType.email, fontSize: 12),
                      const SizedBox(height: 10),
                      // Using CustomButton with toggle logic
                      SizedBox(
                        width: 150,
                        height: 35,
                        child: CustomButton(
                          text: "Edit Profile",
                          onPressed: _editProfile,
                          // If your CustomButton supports color overrides:
                          color: const Color(0xFFFF3B30),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 32),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 17),
                child: const Text(
                  "Personal Details",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 20),

              // --- Form Fields ---
              _buildLabel("Email Address"),
              CustomTextField(
                controller: _emailController,
                prefixIcon: Icons.email_outlined,
                enabled: _isEditing,
              ),

              const SizedBox(height: 16),
              _buildLabel("Username"),
              CustomTextField(
                controller: _usernameController,
                prefixIcon: Icons.person_outline,
                enabled: _isEditing,
              ),

              if (_isEditing) ...[
                const SizedBox(height: 16),
                _buildLabel("Password"),
                CustomTextField(
                  controller: _passwordController,
                  prefixIcon: Icons.lock_outline,
                  obscureText: false,
                  enabled: true,
                ),

                const SizedBox(height: 16),
                _buildLabel("Confirm Password"),
                CustomTextField(
                  controller: _confirmPasswordController,
                  prefixIcon: Icons.lock_outline,
                  obscureText: false,
                  enabled: true,
                ),
              ],

              const SizedBox(height: 32),

              // --- Update Button ---
              if (_isEditing)
                Center(
                  child: SizedBox(
                    width: 350,
                    height: 60,
                    child: CustomButton(
                      text: "Update",
                      onPressed: () {},
                      color: Colors.amber, // Disables button if not editing
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper to build consistent labels
  Widget _buildLabel(String label) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 17),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          // 2. Adjust color based on BOTH editing state AND theme
          color: _isEditing
              ? (isDarkMode ? Colors.white : Colors.black)
              : (isDarkMode ? Colors.white54 : Colors.grey[600]),
        ),
      ),
    );
  }
}
