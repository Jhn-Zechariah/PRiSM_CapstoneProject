/*

FIREBASE AS A BACKEND - replace backend here

 */

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:prism_app/features/auth/domain/model/app_user.dart';
import 'package:prism_app/features/auth/domain/repo/auth_repo.dart';

class FirebaseAuthRepo implements AuthRepo {
  //access to firebase
  final FirebaseAuth firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  //saved user data
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
  Future<AppUser?> registerWithEmailPassword(
    String name,
    String email,
    String password,
  ) async {
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
    } catch (e) {
      throw Exception('An unexpected error occurred: $e');
    }
  }

  //DELETE ACCOUNT
  // @override
  // Future<void> deleteAccount() async {
  //   try {
  //     //get current user
  //     final user = firebaseAuth.currentUser;
  //
  //     //check if theres a user logged in
  //     if (user == null) throw Exception('No user logged in..');
  //
  //     //delete firestore data
  //     await firestore.collection('admins').doc(user.uid).delete();
  //
  //     //delete account
  //     await user.delete();
  //
  //     //log out
  //     await logout();
  //
  //   } catch (e) {
  //     throw Exception('Failed to delete account: $e');
  //   }
  // }

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
    // 1. Sign out of Firebase
    await firebaseAuth.signOut();

    // 2. Sign out of Google
    await GoogleSignIn.instance.signOut();
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

  //GOOGLE SIGN IN
  @override
  Future<AppUser?> googleSignIn() async {
    try {
      final gUser = await GoogleSignIn.instance.authenticate();
      final gAuth = gUser.authentication;

      final credential = GoogleAuthProvider.credential(idToken: gAuth.idToken);
      final userCredential = await firebaseAuth.signInWithCredential(credential);

      final firebaseUser = userCredential.user;
      if (firebaseUser == null) return null;

      final user = AppUser(
        uid: firebaseUser.uid,
        email: firebaseUser.email ?? '',
        username: firebaseUser.displayName ?? '',
      );

      try {
        await createUserDocument(user);
      } catch (e) {
        debugPrint('Firestore write failed: $e');
      }

      return user;
    } catch (e, st) {
      debugPrint('Google sign-in failed: $e\n$st');
      rethrow; // lets the cubit emit AuthError so you can show a message
    }
  }
}
