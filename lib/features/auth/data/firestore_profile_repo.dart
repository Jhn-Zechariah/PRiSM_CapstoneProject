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

      // 1. Update Firebase Auth Profile
      await user.updateDisplayName(newUsername);
      await user.reload(); // Refresh the user to get the new data

      // 2. Update Firestore Document (Using your 'admins' collection)
      await firestore.collection('admins').doc(user.uid).update({
        'username': newUsername,
        'updatedAt': FieldValue.serverTimestamp(),
      });

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

      // 1. Re-authenticate with current password first
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);

      // 2. Update Firebase Auth Email
      await user.verifyBeforeUpdateEmail(newEmail);

      // 3. Update Firestore Document
      await firestore.collection('admins').doc(user.uid).update({
        'email': newEmail,
        'updatedAt': FieldValue.serverTimestamp(),
      });

    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password') {
        throw Exception('Current password is incorrect.');
      }
      throw Exception('Failed to update email: ${e.message}');
    } catch (e) {
      throw Exception('An unexpected error occurred: $e');
    }
  }

  // --- SET INITIAL PASSWORD (FOR GOOGLE USERS) ---
  @override
  Future<void> setInitialPassword(String newPassword) async {
    try {
      final user = firebaseAuth.currentUser;
      if (user == null) throw Exception('No user logged in.');

      // Because they signed in with Google, their session is inherently trusted.
      // Firebase will automatically attach the email/password provider to their account!
      await user.updatePassword(newPassword);

    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw Exception('Session expired. Please log out and log back in with Google before setting a password.');
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

      // 1. Re-authenticate with current password first
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);

      // 2. Update password
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
}