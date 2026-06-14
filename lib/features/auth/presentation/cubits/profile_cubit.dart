import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
        final hasPassword = user.providerData.any((provider) => provider.providerId == 'password');
        
        // Update FCM token whenever user data is loaded (login/app start)
        updateFcmToken(user.uid);

        emit(ProfileLoaded(username: username, email: email, hasPassword: hasPassword));
      } else {
        emit(ProfileError(message: "No user logged in"));
      }
    } catch (e) {
      emit(ProfileError(message: e.toString()));
    }
  }

  // --- Update FCM Token ---
  Future<void> updateFcmToken(String userId) async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await profileRepo.updateFcmToken(userId, token);
      }
    } catch (e) {
      print("Error updating FCM token in Cubit: $e");
    }
  }

  // --- Sync Notification Preferences ---
  Future<void> syncNotificationPreferences(String userId, Map<String, bool> preferences) async {
    try {
      await profileRepo.updateNotificationPreferences(userId, preferences);
    } catch (e) {
      print("Error syncing notification preferences in Cubit: $e");
    }
  }

  // --- Update Username ---
  Future<bool> updateUsername(String newUsername) async {
    try {
      emit(ProfileLoading());
      await profileRepo.updateUsername(newUsername.trim());
      loadUserData();
      return true;
    } catch (e) {
      emit(ProfileError(message: e.toString().replaceAll('Exception: ', '')));
      loadUserData(); 
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
      loadUserData();
      return true;
    } catch (e) {
      emit(ProfileError(message: e.toString().replaceAll('Exception: ', '')));
      loadUserData();
      return false;
    }
  }
}
