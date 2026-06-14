import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../domain/repo/profile_repo.dart';

class FirebaseProfileRepo implements ProfileRepo {
  final FirebaseAuth firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  // --- UPDATE USERNAME ---
  @override
  Future<void> updateUsername(String newUsername) async {
    try {
      final user = firebaseAuth.currentUser;
      if (user == null) throw Exception('No user logged in.');

      await user.updateDisplayName(newUsername);
      await user.reload();

      await firestore.collection('admins').doc(user.uid).set({
        'username': newUsername,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to update username: $e');
    }
  }

  // --- UPDATE EMAIL ---
  @override
  Future<void> updateEmail(String currentPassword, String newEmail) async {
    try {
      final user = firebaseAuth.currentUser;
      if (user == null || user.email == null) throw Exception('No user logged in.');

      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);

      await user.verifyBeforeUpdateEmail(newEmail);

      await firestore.collection('admins').doc(user.uid).set({
        'email': newEmail,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password') {
        throw Exception('Current password is incorrect.');
      }
      throw Exception('Failed to update email: ${e.message}');
    } catch (e) {
      throw Exception('An unexpected error occurred: $e');
    }
  }

  // --- SET INITIAL PASSWORD ---
  @override
  Future<void> setInitialPassword(String newPassword) async {
    try {
      final user = firebaseAuth.currentUser;
      if (user == null) throw Exception('No user logged in.');
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw Exception('Session expired. Please log out and log back in.');
      }
      throw Exception('Failed to set password: ${e.message}');
    } catch (e) {
      throw Exception('An unexpected error occurred: $e');
    }
  }

  // --- UPDATE PASSWORD ---
  @override
  Future<void> updatePassword(String currentPassword, String newPassword, String confirmPassword) async {
    try {
      final user = firebaseAuth.currentUser;
      if (user == null || user.email == null) throw Exception('No user logged in.');

      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);

      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'wrong-password':
          throw Exception('Current password is incorrect.');
        case 'weak-password':
          throw Exception('New password is too weak.');
        default:
          throw Exception('Failed to update password: ${e.message}');
      }
    } catch (e) {
      throw Exception('An unexpected error occurred: $e');
    }
  }

  // --- UPDATE FCM TOKEN ---
  @override
  Future<void> updateFcmToken(String userId, String? token) async {
    try {
      // Use set with merge: true to ensure the field is created even if it doesn't exist
      await firestore.collection('admins').doc(userId).set({
        'fcmToken': token,
        'tokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      print("✅ FCM Token successfully saved to Firestore for user: $userId");
    } catch (e) {
      print("❌ Error updating FCM token in Firestore: $e");
    }
  }

  // --- UPDATE NOTIFICATION PREFERENCES ---
  @override
  Future<void> updateNotificationPreferences(String userId, Map<String, bool> preferences) async {
    try {
      await firestore.collection('admins').doc(userId).set({
        'notificationPreferences': preferences,
        'preferencesUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      print("✅ Notification preferences successfully synced to Firestore for user: $userId");
    } catch (e) {
      print("❌ Error updating notification preferences in Firestore: $e");
    }
  }
}
