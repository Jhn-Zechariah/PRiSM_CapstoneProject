abstract class ProfileRepo {
  // Updates the user's display name
  Future<void> updateUsername(String newUsername);

  // Updates the user's email address
  Future<void> updateEmail(String newEmail, String currentPassword);

  // Changes the password while the user is actively logged in
  Future<void> updatePassword(String currentPassword, String newPassword, String confirmPassword);

  // Sets initial password
  Future<void> setInitialPassword(String newPassword);

  // Updates FCM token for notifications
  Future<void> updateFcmToken(String userId, String? token);

  // Updates specific notification preferences in Firestore
  Future<void> updateNotificationPreferences(String userId, Map<String, bool> preferences);
}
