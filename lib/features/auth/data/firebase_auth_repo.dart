/*

FIREBASE AS A BACKEND - replace backend here

 */

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:prism_app/features/auth/domain/models/app_user.dart';
import 'package:prism_app/features/auth/domain/repo/auth_repo.dart';

class FirebaseAuthRepo implements AuthRepo {

  //access to firebase
  final FirebaseAuth firebaseAuth = FirebaseAuth.instance;

  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  Future<void> createUserDocument(AppUser user) async {
    final docRef = firestore.collection('admins').doc(user.uid);
    final docSnap = await docRef.get();

    if (!docSnap.exists) {
      // Create new document (first time)
      await docRef.set({
        'uid': user.uid,
        'username': user.username,
        'email': user.email,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      // Update without touching username
      await docRef.update({
        'email': user.email,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  //LOG IN WITH EMAIL AND PASS
  @override
  Future<AppUser?> loginWithEmailPassword(String email, String password) async {
    try {
      //attempt sign in
      UserCredential userCredential = await firebaseAuth
          .signInWithEmailAndPassword(email: email, password: password);

      final firebaseUser = userCredential.user;
      if (firebaseUser == null) return null;

      //create user
      AppUser user = AppUser(
        uid: firebaseUser.uid,
        email: email,
        username: firebaseUser.displayName ?? '',
      );

      //create/update firestore document
      await createUserDocument(user);

      //return user
      return user;

    } catch (e) {
      throw Exception('Log in Failed: $e');
    }
  }

  //REGISTER WITH EMAIL AND PASS
  @override
  Future<AppUser?> registerWithEmailPassword(String name, String email, String password) async {
    try {
      //attempt sign up
      UserCredential userCredential = await firebaseAuth
          .createUserWithEmailAndPassword(email: email, password: password);

      final firebaseUser = userCredential.user;
      if (firebaseUser == null) return null;

      //set display name properly
      await firebaseUser.updateDisplayName(name);

      //reload to get updated displayName
      await firebaseUser.reload();

      final updatedUser = firebaseAuth.currentUser;

      //create user
      AppUser user = AppUser(
        uid: updatedUser!.uid,
        email: email,
        username: updatedUser.displayName ?? name,
      );

      //create firestore document
      await createUserDocument(user);

      //return user
      return user;

    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
          throw Exception('No account found with this email.');
        case 'wrong-password':
          throw Exception('Incorrect password.');
        case 'invalid-email':
          throw Exception('Invalid email format.');
        case 'user-disabled':
          throw Exception('This account has been disabled.');
        case 'too-many-requests':
          throw Exception('Too many attempts. Try again later.');
        default:
          throw Exception('Login failed: ${e.message}');
      }
    } catch (e) {
      throw Exception('An unexpected error occurred: $e');
    }
  }

  //DELETE ACCOUNT
  @override
  Future<void> deleteAccount() async {
    try {
      //get current user
      final user = firebaseAuth.currentUser;

      //check if theres a user logged in
      if (user == null) throw Exception('No user logged in..');

      //delete firestore data
      await firestore.collection('admins').doc(user.uid).delete();

      //delete account
      await user.delete();

      //log out
      await logout();

    } catch (e) {
      throw Exception('Failed to delete account: $e');
    }
  }

  //GET CURRENT USER
  @override
  Future<AppUser?> getCurrentUser() async {
    //get current logged in user from firebase
    final firebaseUser = firebaseAuth.currentUser;

    //no logged in user
    if (firebaseUser == null) return null;

    //logged in user exist
    return AppUser(
      uid: firebaseUser.uid,
      email: firebaseUser.email ?? '',
      username: firebaseUser.displayName ?? '',
    );
  }

  //LOG OUT
  @override
  Future<void> logout() async {
    await firebaseAuth.signOut();
  }

  //RESET PASSWORD
  @override
  Future<String> sendPasswordResetEmail(String email) async {
    try {
      await firebaseAuth.sendPasswordResetEmail(email: email);
      return 'Password reset email! Check your email';
    } catch (e) {
      return 'An error occurred: $e';
    }
  }

  //UPDATE PASSWORD
  @override
  Future<void> reauthAndUpdatePassword(
      String currentPassword, String newPassword) async {
    try {
      final user = firebaseAuth.currentUser;
      if (user == null || user.email == null) throw Exception('No user logged in.');

      // re-authenticate with current password first
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);

      // now safe to update
      await user.updatePassword(newPassword);

    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'wrong-password':
          throw Exception('Current password is incorrect.');
        case 'weak-password':
          throw Exception('New password is too weak.');
        case 'requires-recent-login':
          throw Exception('Session expired. Please log in again.');
        default:
          throw Exception('Failed to update password: ${e.message}');
      }
    }
  }

  //GOOGLE SIGN IN
  @override
  Future<AppUser?> googleSignIn() async {
    try {
      await GoogleSignIn.instance.initialize();

      //begin sign-in process
      final GoogleSignInAccount? gUser = await GoogleSignIn.instance.authenticate();

      //user cancelled sign in
      if (gUser == null) return null;

      //obtain details from req
      final GoogleSignInAuthentication gAuth = await gUser.authentication;

      //create credential for user
      final credential = GoogleAuthProvider.credential(
        idToken: gAuth.idToken,
      );

      //sign in with credential
      UserCredential userCredential = await firebaseAuth.signInWithCredential(credential);

      //firebase user (Removed the '!' right here)
      final firebaseUser = userCredential.user;
      if (firebaseUser == null) return null;

      AppUser user = AppUser(
        uid: firebaseUser.uid,
        email: firebaseUser.email ?? '',
        username: firebaseUser.displayName ?? '',
      );

      //create/update firestore document
      await createUserDocument(user);

      return user;

    } catch (e) {
      print("Google Sign-In Error: $e");
      // Ensure we return null if the try block fails!
      return null;
    }
  }
}


