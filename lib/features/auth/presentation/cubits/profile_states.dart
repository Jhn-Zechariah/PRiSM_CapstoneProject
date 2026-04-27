// profile_state.dart
abstract class ProfileState {}

class ProfileInitial extends ProfileState {}

class ProfileLoading extends ProfileState {}

class ProfileLoaded extends ProfileState {
  final String username;
  final String email;
  final bool hasPassword;

  ProfileLoaded({required this.username, required this.email, required this.hasPassword});
}


class ProfileError extends ProfileState {
  final String message;
  ProfileError({required this.message});
}