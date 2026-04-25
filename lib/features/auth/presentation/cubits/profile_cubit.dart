// profile_cubit.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:prism_app/features/auth/presentation/cubits/profile_states.dart';


class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit() : super(ProfileInitial());

  void loadUserData() {
    emit(ProfileLoading()); // Tell UI to show a spinner

    try {
      // The Cubit handles Firebase, NOT the UI
      final user = FirebaseAuth.instance.currentUser;
      final username = user?.displayName ?? "Admin";
      final email = user?.email ?? "No email";

      emit(ProfileLoaded(username: username, email: email)); // Send data to UI
    } catch (e) {
      emit(ProfileError(message: e.toString()));
    }
  }
}