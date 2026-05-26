import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/core/widgets/app_top_bar.dart';
import 'package:prism_app/core/widgets/button.dart';
import '../../../../core/widgets/snackbar.dart';
import '../../../../core/widgets/text.dart';
import '../../../../core/widgets/textfield.dart';
import '../cubits/profile_cubit.dart';
import '../cubits/profile_states.dart';
import '../cubits/auth_cubit.dart';

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
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

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

  void _editProfile() {
    setState(() {
      _isEditing = !_isEditing;
      if (!_isEditing) {
        _passwordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      }
    });
  }

  Future<void> _update() async {
    late final profileCubit = context.read<ProfileCubit>();
    if (_formKey.currentState!.validate()) {
      final currentState = context.read<ProfileCubit>().state;
      String originalUsername = "";
      String originalEmail = "";
      bool hasPassword = true;

      if (currentState is ProfileLoaded) {
        originalUsername = currentState.username;
        originalEmail = currentState.email;
        hasPassword = currentState.hasPassword;
      }

      final newUsername = _usernameController.text.trim();
      final newEmail = _emailController.text.trim();
      final currentPass = _passwordController.text;
      final newPass = _newPasswordController.text;
      final confirmPassword = _confirmPasswordController.text;

      if (newUsername != originalUsername && newUsername.isNotEmpty) {
        final success = await profileCubit.updateUsername(newUsername);
        if (!success || !mounted) return;
        CustomSnackbar.show(
          context: context,
          message: "Username updated successfully!",
        );
      }

      if (newEmail != originalEmail && newEmail.isNotEmpty) {
        if (currentPass.isEmpty) {
          CustomSnackbar.show(
            context: context,
            isError: true,
            message: "Current password is required to change email address!",
          );
          return;
        }
        final isSuccess = await profileCubit.updateEmail(currentPass, newEmail);
        if (isSuccess) {
          if (mounted) {
            CustomSnackbar.show(
              context: context,
              message:
                  "Verification email sent! Please check your inbox and log in again.",
            );
            Navigator.of(context).popUntil((route) => route.isFirst);
            context.read<AuthCubit>().logout();
          }
          return;
        }
      }

      if (newPass.isNotEmpty) {
        if (hasPassword) {
          final success = await profileCubit.updatePassword(
            currentPass,
            newPass,
            confirmPassword,
          );
          if (!success || !mounted) return;
          CustomSnackbar.show(
            context: context,
            message: "Password updated successfully!",
          );
        } else {
          final success = await profileCubit.setInitialPassword(newPass);
          if (success && mounted) {
            CustomSnackbar.show(
              context: context,
              message:
                  "Password set successfully! You can now log in with email and password",
            );
          }
        }
      }

      setState(() {
        _isEditing = false;
        _passwordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      });
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// A read-only display row used inside the "Account Overview" card.
  Widget _buildOverviewRow({
    required IconData icon,
    required String value,
    required bool isDarkMode,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: isDarkMode ? Colors.white24 : Colors.black12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isDarkMode ? Colors.white54 : Colors.black54,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: isDarkMode ? Colors.white : Colors.black87,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A labelled text field used in edit mode.
  Widget _buildLabelledField({
    required String label,
    required TextEditingController controller,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    bool enabled = true,
    required bool isDarkMode,
  }) {
    final borderColor = isDarkMode ? Colors.white24 : Colors.black26;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final fillColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: textColor,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          enabled: enabled,
          validator: validator,
          style: TextStyle(color: textColor, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: fillColor,
            suffixIcon: suffixIcon,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.blueAccent),
            ),
          ),
        ),
      ],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
          }
          if (state is ProfileError) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        builder: (context, state) {
          if (state is ProfileLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          bool hasPassword = true;
          if (state is ProfileLoaded) hasPassword = state.hasPassword;

          final username = state is ProfileLoaded
              ? state.username
              : "Loading...";
          final email = state is ProfileLoaded ? state.email : "Loading...";

          return SafeArea(
            child: Column(
              children: [
                // ── Top bar ──────────────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title changes between view / edit mode
                          AppTopBar(
                            showBackButton: true,
                            title: _isEditing ? "Edit Profile" : "My Profile",
                          ),
                          const SizedBox(height: 24),

                          // ── Profile header ──────────────────────────────
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Avatar – slightly smaller in edit mode to match mockup
                              CircleAvatar(
                                radius: _isEditing ? 40 : 50,
                                backgroundColor: isDarkMode
                                    ? Colors.white10
                                    : Colors.black12,
                                child: Icon(
                                  Icons.person_outline,
                                  color: isDarkMode
                                      ? Colors.white
                                      : Colors.black87,
                                  size: _isEditing ? 44 : 55,
                                ),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      username,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: isDarkMode
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                    Text(
                                      email,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDarkMode
                                            ? Colors.white60
                                            : Colors.black54,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    // Edit / Cancel button
                                    SizedBox(
                                      width: 120,
                                      height: 34,
                                      child: ElevatedButton(
                                        onPressed: _editProfile,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _isEditing
                                              ? const Color(0xFFFFCC00)
                                              : Colors.green,
                                          foregroundColor: _isEditing
                                              ? Colors.black
                                              : Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          elevation: 0,
                                          padding: EdgeInsets.zero,
                                        ),
                                        child: Text(
                                          _isEditing
                                              ? "Cancel"
                                              : "Edit Profile",
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 28),

                          // ── VIEW MODE ────────────────────────────────────
                          if (!_isEditing) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDarkMode
                                    ? const Color(0xFF1E1E1E)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isDarkMode
                                      ? Colors.white12
                                      : Colors.black12,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Account Overview",
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: isDarkMode
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    "Email",
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isDarkMode
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  _buildOverviewRow(
                                    icon: Icons.email_outlined,
                                    value: email,
                                    isDarkMode: isDarkMode,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    "Username",
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isDarkMode
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  _buildOverviewRow(
                                    icon: Icons.person_outline,
                                    value: username,
                                    isDarkMode: isDarkMode,
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // ── EDIT MODE ────────────────────────────────────
                          if (_isEditing) ...[
                            _buildLabelledField(
                              label: "Email Address",
                              controller: _emailController,
                              isDarkMode: isDarkMode,
                            ),
                            const SizedBox(height: 16),
                            _buildLabelledField(
                              label: "Username",
                              controller: _usernameController,
                              isDarkMode: isDarkMode,
                            ),
                            const SizedBox(height: 16),

                            if (hasPassword) ...[
                              _buildLabelledField(
                                label: "Current Password",
                                controller: _passwordController,
                                obscureText: _obscureCurrentPassword,
                                isDarkMode: isDarkMode,
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureCurrentPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: isDarkMode
                                        ? Colors.white54
                                        : Colors.black45,
                                  ),
                                  onPressed: () => setState(() {
                                    _obscureCurrentPassword =
                                        !_obscureCurrentPassword;
                                  }),
                                ),
                                validator: (value) {
                                  if ((value == null || value.isEmpty) &&
                                      (_newPasswordController.text.isNotEmpty ||
                                          _confirmPasswordController
                                              .text
                                              .isNotEmpty)) {
                                    return "Please enter your current password first";
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                            ],

                            _buildLabelledField(
                              label: hasPassword
                                  ? "New Password"
                                  : "Set Account Password",
                              controller: _newPasswordController,
                              obscureText: _obscureNewPassword,
                              isDarkMode: isDarkMode,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureNewPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: isDarkMode
                                      ? Colors.white54
                                      : Colors.black45,
                                ),
                                onPressed: () => setState(() {
                                  _obscureNewPassword = !_obscureNewPassword;
                                }),
                              ),
                              validator: (value) {
                                if ((value == null || value.isEmpty) &&
                                    _confirmPasswordController
                                        .text
                                        .isNotEmpty) {
                                  return "Please enter your new password";
                                }
                                if (value != _confirmPasswordController.text &&
                                    _confirmPasswordController
                                        .text
                                        .isNotEmpty) {
                                  return "Passwords do not match";
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            _buildLabelledField(
                              label: "Confirm password",
                              controller: _confirmPasswordController,
                              obscureText: _obscureConfirmPassword,
                              isDarkMode: isDarkMode,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: isDarkMode
                                      ? Colors.white54
                                      : Colors.black45,
                                ),
                                onPressed: () => setState(() {
                                  _obscureConfirmPassword =
                                      !_obscureConfirmPassword;
                                }),
                              ),
                              validator: (value) {
                                if ((value == null || value.isEmpty) &&
                                    _newPasswordController.text.isNotEmpty) {
                                  return "Please confirm your password";
                                }
                                if (value != _newPasswordController.text &&
                                    _newPasswordController.text.isNotEmpty) {
                                  return "Passwords do not match";
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 28),

                            // ── Update Profile button ──────────────────────
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _update,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(
                                    0xFF2979FF,
                                  ), // blue
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  "Update Profile",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],

                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Log Out button (view mode only, pinned at bottom) ────
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
                            builder: (context) {
                              final isDarkMode =
                                  Theme.of(context).brightness ==
                                  Brightness.dark;

                              return AlertDialog(
                                backgroundColor: isDarkMode
                                    ? const Color(0xFF1E1E1E)
                                    : Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                title: Text(
                                  "Confirm Logout",
                                  style: TextStyle(
                                    color: isDarkMode
                                        ? Colors.white
                                        : Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                content: Text(
                                  "Are you sure you want to log out?",
                                  style: TextStyle(
                                    color: isDarkMode
                                        ? Colors.white70
                                        : Colors.black87,
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(context, false);
                                    },
                                    child: const Text(
                                      "Cancel",
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ),
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.pop(context, true);
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text("Yes"),
                                  ),
                                ],
                              );
                            },
                          );

                          if (shouldLogout == true) {
                            Navigator.pop(context);

                            final authCubit = context.read<AuthCubit>();
                            authCubit.logout();
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: const Text(
                          "Log Out",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
