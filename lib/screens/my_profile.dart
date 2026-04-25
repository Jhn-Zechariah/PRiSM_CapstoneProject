import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/features/auth/presentation/components/app_top_bar.dart';
import 'package:prism_app/features/auth/presentation/components/custom_text.dart';
import 'package:prism_app/features/auth/presentation/components/custom_button.dart';
import 'package:prism_app/features/auth/presentation/components/custom_textfield.dart';
import '../features/auth/presentation/cubits/profile_cubit.dart';
import '../features/auth/presentation/cubits/profile_states.dart';


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

  void _update() {
    //prepare info
    // final String username = _usernameController.text;
    // final String email = _emailController.text;
    // final String password = _passwordController.text;

    if (_formKey.currentState!.validate()) {
      debugPrint("Username: ${_usernameController.text}");
      debugPrint("Email: ${_emailController.text}");
      debugPrint("Current Password: ${_newPasswordController.text}");
      debugPrint("Password: ${_passwordController.text}");
      debugPrint("Confirm Password: ${_confirmPasswordController.text}");

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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        builder: (context, state) {
          // Optional: Show a loading spinner while fetching data
          if (state is ProfileLoading) {
            return const Center(child: CircularProgressIndicator());
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
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: isDarkMode ? Colors.white10 : Colors.black12,
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
                            CustomText(
                              type: TextType.custom,
                              text: state is ProfileLoaded ? state.username : "Loading...",
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            CustomText(
                                type: TextType.custom,
                                text: state is ProfileLoaded ? state.email : "Loading...",
                                fontSize: 12
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: 150,
                              height: 35,
                              child: CustomButton(
                                text: _isEditing? "Cancel" : "Edit Profile",
                                onPressed: _editProfile,
                                backgroundColor: _isEditing ?  Colors.red : null,
                                color: _isEditing ? Colors.white : null,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 17),
                      child: Text(
                        "Personal Details",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // --- Form Fields ---
                    CustomTextField(
                      label: "Email Address",
                      controller: _emailController,
                      prefixIcon: Icons.email_outlined,
                      enabled: _isEditing,
                    ),

                    const SizedBox(height: 16),
                    CustomTextField(
                      label: "Username",
                      controller: _usernameController,
                      prefixIcon: Icons.person_outline,
                      enabled: _isEditing,
                    ),

                    if (_isEditing) ...[
                      const SizedBox(height: 16),
                      CustomTextField(
                        label: "Current Password",
                        controller: _passwordController,
                        prefixIcon: Icons.lock_outline,
                        obscureText: _obscureCurrentPassword,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureCurrentPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: isDarkMode ? Colors.white60 : Colors.black54,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureCurrentPassword = !_obscureCurrentPassword;
                            });
                          },
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty && (_newPasswordController.text.isNotEmpty || _confirmPasswordController.text.isNotEmpty)) return "Please enter your current password first";
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),
                      CustomTextField(
                        label: "New Password",
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
                          if (value == null || value.isEmpty && (_passwordController.text.isNotEmpty || _confirmPasswordController.text.isNotEmpty)) return "Please enter your new password";
                          if (value != _confirmPasswordController.text && _confirmPasswordController.text.isNotEmpty) return "Passwords do not match";
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),
                      CustomTextField(
                        label: "Confirm Password",
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
                              _obscureConfirmPassword = !_obscureConfirmPassword;
                            });
                          },
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty && (_newPasswordController.text.isNotEmpty || _passwordController.text.isNotEmpty)) return "Please confirm your password";
                          if (value != _newPasswordController.text && _newPasswordController.text.isNotEmpty) return "Passwords do not match";
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