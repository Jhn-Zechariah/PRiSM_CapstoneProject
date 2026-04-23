import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminInfoWidget extends StatelessWidget {
  const AdminInfoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    // Get current Firebase user
    final user = FirebaseAuth.instance.currentUser;

    // Fallback values if null
    final username = user?.displayName ?? "Admin";
    final email = user?.email ?? "No email";

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            username,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            email,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
