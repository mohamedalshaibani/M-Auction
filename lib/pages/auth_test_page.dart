import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthTestPage extends StatefulWidget {
  const AuthTestPage({super.key});

  @override
  State<AuthTestPage> createState() => _AuthTestPageState();
}

class _AuthTestPageState extends State<AuthTestPage> {
  final _phone = TextEditingController();
  final _code = TextEditingController();

  String? _verificationId;
  String _status = '';

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    setState(() => _status = 'Sending code...');
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: _phone.text.trim(),
        verificationCompleted: (cred) async {
          await FirebaseAuth.instance.signInWithCredential(cred);
          if (mounted) {
            setState(() => _status = 'Signed in ✅ (auto)');
            Navigator.of(context).pushReplacementNamed('/authGate');
          }
        },
        verificationFailed: (e) {
          setState(() => _status = 'Error: ${e.message}');
        },
        codeSent: (verificationId, _) {
          _verificationId = verificationId;
          setState(() => _status = 'Code sent ✅');
        },
        codeAutoRetrievalTimeout: (verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
  }

  Future<void> _verifyCode() async {
    if (_verificationId == null) {
      setState(() => _status = 'Please send code first');
      return;
    }
    setState(() => _status = 'Verifying...');
    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _code.text.trim(),
      );
      await FirebaseAuth.instance.signInWithCredential(cred);
      if (mounted) {
        setState(() => _status = 'Signed in ✅');
        Navigator.of(context).pushReplacementNamed('/authGate');
      }
    } catch (e) {
      setState(() => _status = 'Verification failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Auth Test')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'For web testing, use Firebase Test phone numbers from Firebase Console',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phone,
              decoration: const InputDecoration(
                labelText: 'Phone (+971...)',
                hintText: 'Use test phone number from Firebase Console',
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _sendCode,
              child: const Text('Send Code'),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _code,
              decoration: const InputDecoration(
                labelText: 'SMS Code',
                hintText: 'Enter verification code',
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _verifyCode,
              child: const Text('Verify & Sign In'),
            ),
            const SizedBox(height: 24),
            Text(
              _status,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
