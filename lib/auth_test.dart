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
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: _phone.text.trim(),
      verificationCompleted: (cred) async {
        await FirebaseAuth.instance.signInWithCredential(cred);
        setState(() => _status = 'Signed in ✅ (auto)');
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
  }

  Future<void> _verifyCode() async {
    if (_verificationId == null) return;
    setState(() => _status = 'Verifying...');
    final cred = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: _code.text.trim(),
    );
    await FirebaseAuth.instance.signInWithCredential(cred);
    setState(() => _status = 'Signed in ✅');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Auth Test')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _phone,
              decoration: const InputDecoration(
                labelText: 'Phone (+971...)',
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
              decoration: const InputDecoration(labelText: 'SMS Code'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _verifyCode,
              child: const Text('Verify & Sign In'),
            ),
            const SizedBox(height: 24),
            Text(_status),
          ],
        ),
      ),
    );
  }
}