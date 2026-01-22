import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_service.dart';

class CreateProfilePage extends StatefulWidget {
  const CreateProfilePage({super.key});

  @override
  State<CreateProfilePage> createState() => _CreateProfilePageState();
}

class _CreateProfilePageState extends State<CreateProfilePage> {
  final _displayNameController = TextEditingController();
  final _firestoreService = FirestoreService();
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'No user logged in');
      return;
    }

    final displayName = _displayNameController.text.trim();
    if (displayName.isEmpty) {
      setState(() => _error = 'Display name cannot be empty');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      await _firestoreService.createUserAndWallet(
        uid: user.uid,
        displayName: displayName,
        phoneNumber: user.phoneNumber ?? '',
      );

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/authGate');
      }
    } catch (e) {
      setState(() {
        _error = 'Error creating profile: $e';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Profile')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _displayNameController,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                hintText: 'Enter your display name',
              ),
              enabled: !_isSaving,
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ElevatedButton(
              onPressed: _isSaving ? null : _saveProfile,
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
