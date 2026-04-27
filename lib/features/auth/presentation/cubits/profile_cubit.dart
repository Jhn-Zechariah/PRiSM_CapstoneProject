import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:prism_app/features/auth/presentation/cubits/profile_states.dart';
import '../../domain/repo/profile_repo.dart';

class ProfileCubit extends Cubit<ProfileState> {
  final ProfileRepo profileRepo;

  ProfileCubit({required this.profileRepo}) : super(ProfileInitial());

  // --- Load Current Data ---
  void loadUserData() {
    emit(ProfileLoading());

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final username = user.displayName ?? "Admin";
        final email = user.email ?? "No email";
        //Check if the user has a password provider attached to their account
        final hasPassword = user.providerData.any((provider) => provider.providerId == 'password');
        emit(ProfileLoaded(username: username, email: email, hasPassword: hasPassword));
      } else {
        emit(ProfileError(message: "No user logged in"));
      }
    } catch (e) {
      emit(ProfileError(message: e.toString()));
    }
  }

  // --- Update Username ---
  Future<bool> updateUsername(String newUsername) async {
    try {
      emit(ProfileLoading());
      await profileRepo.updateUsername(newUsername.trim());

      // Reload to show the new data
      loadUserData();
      return true;
    } catch (e) {
      emit(ProfileError(message: e.toString().replaceAll('Exception: ', '')));
      loadUserData(); // Revert back to safe state
      return false;
    }
  }

  // --- Update Email ---
  Future<bool> updateEmail(String currentPassword, String newEmail) async {
    try {
      emit(ProfileLoading());
      await profileRepo.updateEmail(currentPassword, newEmail.trim());

      loadUserData();
      return true;
    } catch (e) {
      emit(ProfileError(message: e.toString().replaceAll('Exception: ', '')));
      loadUserData();
      return false;
    }
  }

  // --- Set Initial Password ---
  Future<bool> setInitialPassword(String newPassword) async {
    try {
      emit(ProfileLoading());
      await profileRepo.setInitialPassword(newPassword);
      loadUserData();
      return true;
    } catch (e) {
      emit(ProfileError(message: e.toString().replaceAll('Exception: ', '')));
      loadUserData();
      return false;
    }
  }

  // --- Update Password ---
  Future<bool> updatePassword(String currentPassword, String newPassword, String confirmPasword) async {
    try {
      emit(ProfileLoading());
      await profileRepo.updatePassword(currentPassword, newPassword, confirmPasword);

      // Passwords don't show on screen, but we still reload to reset the loading state
      loadUserData();
      return true;
    } catch (e) {
      emit(ProfileError(message: e.toString().replaceAll('Exception: ', '')));
      loadUserData();
      return false;
    }
  }
}