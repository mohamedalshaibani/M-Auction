import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_service.dart';
import 'login_phone_page.dart';
import 'create_profile_page.dart';
import 'home_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final FirestoreService _firestoreService = FirestoreService();
  String? _cachedUserId;
  Future<bool>? _cachedUserExistsFuture;

  Future<bool> _getUserExistsFuture(String uid) {
    if (_cachedUserId != uid || _cachedUserExistsFuture == null) {
      _cachedUserId = uid;
      _cachedUserExistsFuture = _firestoreService.userExists(uid);
    }
    return _cachedUserExistsFuture!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Handle StreamBuilder errors
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Auth Error')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Authentication Error',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // If waiting for initial auth state, show loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final user = snapshot.data;

        // User not logged in -> return LoginPhonePage
        if (user == null) {
          // Clear cache when user logs out
          _cachedUserId = null;
          _cachedUserExistsFuture = null;
          return const LoginPhonePage();
        }

        // User logged in -> check if user exists in Firestore
        return FutureBuilder<bool>(
          future: _getUserExistsFuture(user.uid),
          builder: (context, futureSnapshot) {
            // Handle FutureBuilder errors
            if (futureSnapshot.hasError) {
              return Scaffold(
                appBar: AppBar(title: const Text('Profile Check Error')),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          'Error Checking Profile',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          futureSnapshot.error.toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // While checking Firestore, show loading with text
            if (futureSnapshot.connectionState == ConnectionState.waiting) {
              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Checking profile...',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey,
                            ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final exists = futureSnapshot.data ?? false;

            if (exists) {
              // User exists -> return HomePage
              return const HomePage();
            } else {
              // User doesn't exist -> return CreateProfilePage
              return const CreateProfilePage();
            }
          },
        );
      },
    );
  }
}
