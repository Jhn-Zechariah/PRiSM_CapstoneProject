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
    // Ask the Cubit to load the data instead of calling Firebase directly!
    // Wrap the Cubit call in this callback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Now this will only run AFTER the BlocConsumer is fully built and listening!
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
    });
  }

  Future<void> _update() async {
    late final profileCubit = context.read<ProfileCubit>();
    if (_formKey.currentState!.validate()) {
      // 1. Get the original values to compare against
      final currentState = context.read<ProfileCubit>().state;
      String originalUsername = "";
      String originalEmail = "";
      bool hasPassword = true;

      if (currentState is ProfileLoaded) {
        originalUsername = currentState.username;
        originalEmail = currentState.email;
        hasPassword = currentState.hasPassword; //
      }

      // 2. Grab the inputs
      final newUsername = _usernameController.text.trim();
      final newEmail = _emailController.text.trim();
      final currentPass = _passwordController.text;
      final newPass = _newPasswordController.text;
      final confirmPassword = _confirmPasswordController.text;

      // 3. Trigger individual updates based on what actually changed

      // Did they change their username?
      if (newUsername != originalUsername && newUsername.isNotEmpty) {
        final success = await profileCubit.updateUsername(newUsername);

        // Stop if the update failed and make sure the screen hasn't been closed during the await
        if (!success || !mounted) return;

        // Since we didn't return, success is true! Show the snackbar.
        CustomSnackbar.show(
          context: context,
          message: "Username updated successfully!",
        );
      }

      // Did they change their email?
      if (newEmail != originalEmail && newEmail.isNotEmpty) {
        if (currentPass.isEmpty) {
          CustomSnackbar.show(
            context: context,
            isError: true,
            message: "Current password is required to change email address!",
          );
          return; // Stop execution
        }
        // Capture the success result from the Cubit
        final isSuccess = await profileCubit.updateEmail(currentPass, newEmail);
        if (isSuccess) {
          // Check if the widget is still mounted before showing UI
          if (mounted) {
            // 1. Show the success message
            CustomSnackbar.show(
              context: context,
              message:
                  "Verification email sent! Please check your inbox and log in again.",
            );

            //Clear the navigation stack so the Profile screen goes away!
            Navigator.of(context).popUntil((route) => route.isFirst);

            // 2. Trigger the AuthCubit to log the user out
            context.read<AuthCubit>().logout();
          }

          // 3. Stop running the rest of the update function so we don't try
          // to update the password right as they are being logged out!
          return;
        } else {}
      }

      // Did they enter a new password?
      if (newPass.isNotEmpty) {
        // If they already have a password, do the normal update
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
        }
        //If they DON'T have a password, set it!
        else {
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

      // 4. Close editing mode and clean up
      setState(() {
        _isEditing = false;
        _passwordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
      // Wrap the body in a BlocConsumer
      body: BlocConsumer<ProfileCubit, ProfileState>(
        listener: (context, state) {
          // When the Cubit successfully loads the data, update the controllers
          if (state is ProfileLoaded) {
            _emailController.text = state.email;
            _usernameController.text = state.username;
          }

          // Optional: Show an error snackbar if something fails
          if (state is ProfileError) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        builder: (context, state) {
          bool hasPassword = true;

          // Optional: Show a loading spinner while fetching data
          if (state is ProfileLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is ProfileLoaded) {
            hasPassword = state.hasPassword; // Grab the flag from the state!
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppTopBar(showBackButton: true, title: "My Profile"),
                    const SizedBox(height: 24),

                    // --- Profile Header ---
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: isDarkMode
                                ? Colors.white10
                                : Colors.black12,
                            child: Icon(
                              Icons.person_outline,
                              color: isDarkMode ? Colors.white : Colors.black87,
                              size: 55,
                            ),
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CustomText(
                                type: TextType.custom,
                                text: state is ProfileLoaded
                                    ? state.username
                                    : "Loading...",
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              CustomText(
                                type: TextType.custom,
                                text: state is ProfileLoaded
                                    ? state.email
                                    : "Loading...",
                                fontSize: 12,
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: 140,
                                height: 35,
                                child: CustomButton(
                                  text: _isEditing ? "Cancel" : "Edit Profile",
                                  borderColor: false,
                                  onPressed: _editProfile,
                                  backgroundColor: _isEditing
                                      ? Colors.red
                                      : null,
                                  color: _isEditing ? Colors.white : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 17),
                      child: Text(
                        "Personal Details",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // --- Form Fields ---
                    CustomTextField(
                      label: "Email Address",
                      border: 20,
                      controller: _emailController,
                      prefixIcon: Icons.email_outlined,
                      enabled: _isEditing,
                    ),

                    const SizedBox(height: 16),
                    CustomTextField(
                      label: "Username",
                      border: 20,
                      controller: _usernameController,
                      prefixIcon: Icons.person_outline,
                      enabled: _isEditing,
                    ),

                    if (_isEditing) ...[
                      const SizedBox(height: 16),

                      if (hasPassword) ...[
                        CustomTextField(
                          label: "Current Password",
                          border: 20,
                          controller: _passwordController,
                          prefixIcon: Icons.lock_outline,
                          obscureText: _obscureCurrentPassword,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureCurrentPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: isDarkMode
                                  ? Colors.white60
                                  : Colors.black54,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureCurrentPassword =
                                    !_obscureCurrentPassword;
                              });
                            },
                          ),
                          validator: (value) {
                            if (value == null ||
                                value.isEmpty &&
                                    (_newPasswordController.text.isNotEmpty ||
                                        _confirmPasswordController
                                            .text
                                            .isNotEmpty))
                              return "Please enter your current password first";
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],

                      CustomTextField(
                        label: hasPassword
                            ? "New Password"
                            : "Set Account Password",
                        border: 20,
                        controller: _newPasswordController,
                        prefixIcon: Icons.lock_outline,
                        obscureText: _obscureNewPassword,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureNewPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: isDarkMode ? Colors.white60 : Colors.black54,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureNewPassword = !_obscureNewPassword;
                            });
                          },
                        ),
                        validator: (value) {
                          if (value == null ||
                              value.isEmpty &&
                                  _confirmPasswordController.text.isNotEmpty)
                            return "Please enter your new password";
                          if (value != _confirmPasswordController.text &&
                              _confirmPasswordController.text.isNotEmpty)
                            return "Passwords do not match";
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),
                      CustomTextField(
                        label: "Confirm Password",
                        border: 20,
                        controller: _confirmPasswordController,
                        prefixIcon: Icons.lock_outline,
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
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword;
                            });
                          },
                        ),
                        validator: (value) {
                          if (value == null ||
                              value.isEmpty &&
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

                      const SizedBox(height: 32),

                      // --- Update Button ---
                      Center(
                        child: SizedBox(
                          width: 350,
                          height: 60,
                          child: CustomButton(
                            text: "Update",
                            borderColor: false,
                            onPressed: () {
                              _update();
                              // TODO: Dispatch an update event to your Cubit here!
                            },
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
