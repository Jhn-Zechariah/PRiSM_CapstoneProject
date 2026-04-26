
abstract class ProfileRepo {
  // Updates the user's display name
  Future<void> updateUsername(String newUsername);

  // Updates the user's email address
  Future<void> updateEmail(String newEmail, String currentPassword);

  // Changes the password while the user is actively logged in
  Future<void> updatePassword(String currentPassword, String newPassword, String confirmPassword);

  // Add this to your abstract class
  Future<void> setInitialPassword(String newPassword);
}