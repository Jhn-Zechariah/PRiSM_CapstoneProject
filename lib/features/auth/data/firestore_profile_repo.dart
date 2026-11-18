import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  static final Future<String> _installationId = _loadInstallationId();

  static Future<String> _loadInstallationId() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'notificationInstallationId';
    final saved = prefs.getString(key);
    if (saved != null) return saved;

    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    if (!await prefs.setString(key, id)) {
      throw StateError('Could not save notification installation ID');
    }
    return id;
  }

  @override
  Future<void> updateFcmToken(String userId, String? token) async {
    final id = await _installationId;
    if (firebaseAuth.currentUser?.uid != userId) return;
    final account = firestore.collection('admins').doc(userId);
    final device = account.collection('notificationDevices').doc(id);
    if (token == null) {
      await device.delete();
      return;
    }

    await firestore.runTransaction((transaction) async {
      final profile = await transaction.get(account);
      transaction.set(device, {
        'token': token,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (profile.data()?['fcmToken'] == token) {
        transaction.update(account, {'fcmToken': FieldValue.delete()});
      }
    });
  }

  // --- UPDATE NOTIFICATION PREFERENCES ---
  @override
  Future<void> updateNotificationPreferences(String userId, Map<String, bool> preferences) async {
    try {
      await firestore.collection('admins').doc(userId).set({
        'notificationPreferences': preferences,
        'preferencesUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      print("✅ Notification preferences successfully synced to Firestore");
    } catch (e) {
      print("❌ Error updating notification preferences in Firestore: $e");
    }
  }
}
