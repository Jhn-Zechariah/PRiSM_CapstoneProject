/*

AUTH PAGE - Determines whether to show login/sign up

 */

import 'package:flutter/cupertino.dart';
import 'package:prism_app/features/auth/presentation/pages/login_screen.dart';
import 'package:prism_app/features/auth/presentation/pages/signup_screen.dart';

class AuthPage extends StatefulWidget {
  final VoidCallback onThemeToggle;
  const AuthPage({super.key, required this.onThemeToggle});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {

  //initially shows login page
  bool showLoginPage = true;

  //toggle between pages
  void togglePages(){
    setState(() {
      showLoginPage = !showLoginPage;
    });
  }

  @override
  Widget build(BuildContext context) {
    if(showLoginPage){
      return LoginScreen(
        onThemeToggle: widget.onThemeToggle,
        togglePages: togglePages);
    }else{
      return SignupScreen(
        onThemeToggle: widget.onThemeToggle,
        togglePages: togglePages);
    }
  }
}
