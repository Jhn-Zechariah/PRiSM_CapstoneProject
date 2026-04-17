/*

Responsible for state management --> show appropriate data on the screen

 */

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/features/auth/domain/models/app_user.dart';
import 'package:prism_app/features/auth/domain/repo/auth_repo.dart';
import 'package:prism_app/features/auth/presentation/cubits/auth_states.dart';

class AuthCubit extends Cubit<AuthState>{
  final AuthRepo authRepo;
  AppUser? _currentUser;

  AuthCubit({required this.authRepo}) : super(AuthInitial());


  //get current user
  AppUser? get currentUser => _currentUser;

  //Check if users is authenticated
  void checkAuth() async{
    //loading
    emit(AuthLoading());

    //get current user
    final AppUser? user = await authRepo.getCurrentUser();

    //check if there is a user
    if(user != null){
      _currentUser = user;
      emit(Authenticated(user));
    }else{
      emit(Unauthenticated());
    }
  }

  //Log in with email + password
  Future<void> login(String email, String password) async{
      try{
        emit(AuthLoading());
        final user = await authRepo.loginWithEmailPassword(email, password);

        if(user != null){
          _currentUser = user;
          emit(Authenticated(user));
        } else{
          emit(Unauthenticated());
        }
      }catch (e) {
        emit(AuthError(e.toString()));
        emit(Unauthenticated());
      }
  }

  //Register email
  Future<void> register(String? name, String email, String password) async{
    try{
      emit(AuthLoading());
      final user = await authRepo.registerWithEmailPassword(name, email, password);

      if(user != null){
        _currentUser = user;
        emit(Authenticated(user));
      } else{
        emit(Unauthenticated());
      }
    }catch (e) {
      emit(AuthError(e.toString()));
      emit(Unauthenticated());
    }
  }

  //Logout
  Future<void> logout() async {
    emit(AuthLoading());
    await authRepo.logout();
    emit(Unauthenticated());
  }

  //Reset pass
  Future<String> forgotPassword(String email) async {
    try{
      final message = await authRepo.sendPasswordResetEmail(email);
      return message;
    }catch (e) {
      return e.toString();
    }
  }

  //Delete account
  Future<void> deleteAccount() async {
    try{
      emit(AuthLoading());
      await authRepo.deleteAccount();
      emit(Unauthenticated());
    }catch (e) {
      emit(AuthError(e.toString()));
      emit(Unauthenticated());
    }
  }

  //Sign in with google
  Future<void> googleSignIn() async {
    try{
      emit(AuthLoading());
      final user = await authRepo.googleSignIn();

      if(user != null){
        _currentUser = user;
        debugPrint("User: ${user.email}");
        emit(Authenticated(user));
      } else{
        emit(Unauthenticated());
      }
    }catch (e) {
      emit(AuthError(e.toString()));
      emit(Unauthenticated());
    }
  }

}