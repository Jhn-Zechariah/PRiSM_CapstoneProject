/*

FIREBASE AS A BACKEND - replace backend here

 */

import 'package:firebase_auth/firebase_auth.dart';
import 'package:prism_app/features/auth/domain/models/app_user.dart';
import 'package:prism_app/features/auth/domain/repo/auth_repo.dart';

class FirebaseAuthRepo implements AuthRepo {

  //access to firebase
  final FirebaseAuth firebaseAuth = FirebaseAuth.instance;

  //LOG IN WITH EMAIL AND PASS
  @override
  Future<AppUser?> loginWithEmailPassword(String email, String password) async {
  try{
  //attempt sign in
    UserCredential userCredential = await firebaseAuth
        .signInWithEmailAndPassword(email: email, password: password);

  //create user
    AppUser user = AppUser(uid: userCredential.user!.uid,email: email,);
  //return user
    return user;
  }
  //catch errors..
  catch(e){
    throw Exception('Log in Failed: $e');
   }
  }

  //REGISTER WITH EMAIL AND PASS
  @override
  Future<AppUser?> registerWithEmailPassword(String name, String email, String password) async {
    try{
      //attempt sign up
      UserCredential userCredential = await firebaseAuth
          .createUserWithEmailAndPassword(email: email, password: password);

      //create user
      AppUser user = AppUser(uid: userCredential.user!.uid, email: email,);

      //return user
      return user;
    }
    //catch errors..
    catch(e){
      throw Exception('Registration Failed: $e');
    }
  }

  //DELETE ACCOUNT
  @override
  Future<void> deleteAccount() async{
    try{
      //get current user
      final user = firebaseAuth.currentUser;

      //check if theres a user logged in
      if(user == null) throw Exception('No user logged in..');

      //delete account
      await user.delete();

      //log out
      await logout();
    }
    catch (e) {
      throw Exception('Failed to delete account: $e');
    }

  }

  //GET CURRENT USER
  @override
  Future<AppUser?> getCurrentUser() async {
    //get current logged in user from firebase
    final firebaseUser = firebaseAuth.currentUser;

    //no logged in user
    if(firebaseUser == null) return null;

    //logged in user exist
    return AppUser(uid: firebaseUser.uid, email: firebaseUser.email!);
  }

  //LOG OUT
  @override
  Future<void> logout() async {
    await firebaseAuth.signOut();
  }

  //RESET PASSWORD
  @override
  Future<String> sendPasswordResetEmail(String email) async {
    try{
      await firebaseAuth.sendPasswordResetEmail(email: email);
      return 'Password reset email! Check your email';
    }
    catch (e) {
      return 'An error occurred: $e';
    };
  }
}