import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/core/widgets/app_top_bar.dart';
import '../../../../core/widgets/button.dart';
import '../../../../core/widgets/confirmation_box.dart';
import '../../../../core/widgets/snackbar.dart';
import '../components/password_field.dart';
import '../cubits/profile_cubit.dart';
import '../cubits/profile_states.dart';
import '../cubits/auth_cubit.dart';
// 🆕 Add your new imports here:
// import 'path/to/custom_password_field.dart';
// import 'path/to/dialog_utils.dart';

class MyProfile extends StatefulWidget {
  const MyProfile({super.key});

  @override
  State<MyProfile> createState() => _MyProfileState();
}

class _MyProfileState extends State<MyProfile> {
  bool _isEditing = false;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProfileCubit>().loadUserData();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  void _toggleEditMode() {
    setState(() {
      _isEditing = !_isEditing;
      if (!_isEditing) {
        _passwordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      }
    });
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final profileCubit = context.read<ProfileCubit>();
    final currentState = profileCubit.state;
    if (currentState is! ProfileLoaded) return;

    final newUsername = _usernameController.text.trim();
    final newEmail = _emailController.text.trim();
    final currentPass = _passwordController.text;
    final newPass = _newPasswordController.text;

    // 1. Update Username
    if (newUsername != currentState.username && newUsername.isNotEmpty) {
      final success = await profileCubit.updateUsername(newUsername);
      if (success && mounted) CustomSnackbar.show(context: context, message: "Username updated!");
    }

    // 2. Update Email
    if (newEmail != currentState.email && newEmail.isNotEmpty) {
      if (currentPass.isEmpty) {
        CustomSnackbar.show(context: context, isError: true, message: "Current password required for email change!");
        return;
      }
      if (await profileCubit.updateEmail(currentPass, newEmail) && mounted) {
        CustomSnackbar.show(context: context, message: "Verification email sent! Please log in again.");
        Navigator.of(context).popUntil((route) => route.isFirst);
        context.read<AuthCubit>().logout();
        return;
      }
    }

    // 3. Update/Set Password
    if (newPass.isNotEmpty) {
      bool success = currentState.hasPassword
          ? await profileCubit.updatePassword(currentPass, newPass, _confirmPasswordController.text)
          : await profileCubit.setInitialPassword(newPass);

      if (success && mounted) CustomSnackbar.show(context: context, message: "Password updated successfully!");
    }

    _toggleEditMode();
  }

  // ── UI BUILDERS ─────────────────────────────────────────────────────────

  Widget _buildViewMode(String email, String username, bool isDarkMode) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDarkMode ? Colors.white12 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Account Overview", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.black87)),
          const SizedBox(height: 16),
          Text("Email", style: TextStyle(fontSize: 14, color: isDarkMode ? Colors.white : Colors.black87)),
          const SizedBox(height: 5),
          _buildOverviewRow(Icons.email_outlined, email, isDarkMode),
          const SizedBox(height: 16),
          Text("Username", style: TextStyle(fontSize: 14, color: isDarkMode ? Colors.white : Colors.black87)),
          const SizedBox(height: 5),
          _buildOverviewRow(Icons.person_outline, username, isDarkMode),
        ],
      ),
    );
  }

  Widget _buildEditMode(bool hasPassword, bool isDarkMode) {
    return Column(
      children: [
        _buildLabelledField("Email Address", _emailController, isDarkMode),
        const SizedBox(height: 16),
        _buildLabelledField("Username", _usernameController, isDarkMode),
        const SizedBox(height: 16),

        if (hasPassword) ...[
          CustomPasswordField(
            label: "Current Password",
            controller: _passwordController,
            isDarkMode: isDarkMode,
            validator: (val) => (val == null || val.isEmpty) && (_newPasswordController.text.isNotEmpty)
                ? "Please enter current password" : null,
          ),
          const SizedBox(height: 16),
        ],

        CustomPasswordField(
          label: hasPassword ? "New Password" : "Set Account Password",
          controller: _newPasswordController,
          isDarkMode: isDarkMode,
          validator: (val) {
            if ((val == null || val.isEmpty) && _confirmPasswordController.text.isNotEmpty) return "Please enter new password";
            if (val != _confirmPasswordController.text && _confirmPasswordController.text.isNotEmpty) return "Passwords do not match";
            return null;
          },
        ),
        const SizedBox(height: 16),

        CustomPasswordField(
          label: "Confirm password",
          controller: _confirmPasswordController,
          isDarkMode: isDarkMode,
          validator: (val) {
            if ((val == null || val.isEmpty) && _newPasswordController.text.isNotEmpty) return "Please confirm password";
            if (val != _newPasswordController.text && _newPasswordController.text.isNotEmpty) return "Passwords do not match";
            return null;
          },
        ),
        const SizedBox(height: 28),

        // 🔹 Using your global CustomButton for the main save action
        CustomButton(
          text: "Update Profile",
          onPressed: _updateProfile,
          backgroundColor: const Color(0xFF2979FF), // Matches your previous blue color
          color: Colors.white,
          border: 12,
          borderColor: false,
        ),
      ],
    );
  }

  Widget _buildOverviewRow(IconData icon, String value, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: isDarkMode ? Colors.white24 : Colors.black12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: isDarkMode ? Colors.white54 : Colors.black54),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: TextStyle(color: isDarkMode ? Colors.white : Colors.black87))),
        ],
      ),
    );
  }

  Widget _buildLabelledField(String label, TextEditingController controller, bool isDarkMode) {
    final borderColor = isDarkMode ? Colors.white24 : Colors.black26;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textColor)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          style: TextStyle(color: textColor, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.blueAccent)),
          ),
        ),
      ],
    );
  }

  // ── MAIN BUILD ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
      body: BlocConsumer<ProfileCubit, ProfileState>(
        listener: (context, state) {
          if (state is ProfileLoaded) {
            _emailController.text = state.email;
            _usernameController.text = state.username;
          } else if (state is ProfileError) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        builder: (context, state) {
          if (state is ProfileLoading) return const Center(child: CircularProgressIndicator());

          final isLoaded = state is ProfileLoaded;
          final username = isLoaded ? state.username : "Loading...";
          final email = isLoaded ? state.email : "Loading...";
          final hasPassword = isLoaded ? state.hasPassword : true;

          return SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppTopBar(showBackButton: true, title: _isEditing ? "Edit Profile" : "My Profile"),
                          const SizedBox(height: 24),

                          // Header Profile Info
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 50,
                                backgroundColor: isDarkMode ? Colors.white10 : Colors.black12,
                                child: Icon(Icons.person_outline, color: isDarkMode ? Colors.white : Colors.black87, size: 55),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(username, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.black87)),
                                    Text(email, style: TextStyle(fontSize: 12, color: isDarkMode ? Colors.white60 : Colors.black54)),
                                    const SizedBox(height: 8),
                                    // 🔹 Wrapped in a slightly taller SizedBox because CustomButton uses a size 18 font by default
                                    SizedBox(
                                      width: 120,
                                      height: 32,
                                      child: CustomButton(
                                        text: _isEditing ? "Cancel" : "Edit Profile",
                                        onPressed: _toggleEditMode,
                                        backgroundColor: _isEditing ? const Color(0xFFFFCC00) : Colors.green,
                                        color: _isEditing ? Colors.black : Colors.white,
                                        border: 8,
                                        elevation: 0,
                                        fontSize: 14,
                                        borderColor: false, // Turn off the black border for this specific button
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),

                          // View vs Edit Mode Toggles Here
                          if (!_isEditing) _buildViewMode(email, username, isDarkMode)
                          else _buildEditMode(hasPassword, isDarkMode),

                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ),

                // Logout Button
                if (!_isEditing)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () async {
                          final shouldLogout = await showDialog<bool>(
                            context: context,
                            builder: (context) => const CustomConfirmDialog(
                              title: "Confirm Logout",
                              content: "Are you sure you want to log out?",
                              confirmText: "Yes",
                              confirmColor: Colors.red, // Keeps the red aesthetic for logging out
                            ),
                          );

                          if (shouldLogout == true && context.mounted) {
                            context.read<AuthCubit>().logout();
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red, width: 1.5),
                        ),
                        child: const Text("Log Out", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}