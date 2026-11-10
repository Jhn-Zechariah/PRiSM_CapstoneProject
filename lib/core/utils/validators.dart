/// Shared form validators, so the same rules apply on every screen.
class Validators {
  Validators._();

  static final RegExp _emailRegex =
      RegExp(r'^[\w.+\-]+@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}$');

  static const int minUsernameLength = 3;
  static const int maxUsernameLength = 30;
  static const int minPasswordLength = 6; // Firebase Auth minimum

  /// Returns an error message, or null if [value] is a valid email.
  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please enter your email';
    if (!_emailRegex.hasMatch(v)) return 'Please enter a valid email';
    return null;
  }

  /// Returns an error message, or null if [value] is a valid username.
  static String? username(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please enter a username';
    if (v.length < minUsernameLength) {
      return 'Username must be at least $minUsernameLength characters';
    }
    if (v.length > maxUsernameLength) {
      return 'Username must be at most $maxUsernameLength characters';
    }
    return null;
  }

  /// Returns an error message, or null if [value] is long enough to be
  /// accepted as a new password.
  static String? newPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Please enter a password';
    if (v.length < minPasswordLength) {
      return 'Password must be at least $minPasswordLength characters';
    }
    return null;
  }
}
