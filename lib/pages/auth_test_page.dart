import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../widgets/unified_app_bar.dart';

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
  
  // Dev mode flag for simulator builds - DEBUG-only, cannot be enabled in release
  // kDebugMode is a compile-time constant that is false in release builds
  static const bool kDevBypassOtp = kDebugMode;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!mounted) return;
    
    setState(() => _status = 'Sending code...');
    
    final phoneNumber = _phone.text.trim();
    if (phoneNumber.isEmpty) {
      if (mounted) {
        setState(() => _status = 'Please enter a phone number');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a phone number')),
        );
      }
      return;
    }
    
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (cred) async {
          try {
            await FirebaseAuth.instance.signInWithCredential(cred);
            if (mounted) {
              setState(() => _status = 'Signed in ✅ (auto)');
              Navigator.of(context).pushReplacementNamed('/authGate');
            }
          } catch (e) {
            debugPrint('Error signing in with credential: $e');
            if (mounted) {
              setState(() => _status = 'Sign-in error: $e');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Sign-in error: ${e.toString()}')),
              );
            }
          }
        },
        verificationFailed: (e) {
          debugPrint('Phone verification failed: ${e.code} - ${e.message}');
          if (mounted) {
            setState(() => _status = 'Error: ${e.message ?? e.code}');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Verification failed: ${e.message ?? e.code}'),
                duration: const Duration(seconds: 5),
              ),
            );
          }
        },
        codeSent: (verificationId, _) {
          debugPrint('Verification code sent: $verificationId');
          _verificationId = verificationId;
          if (mounted) {
            setState(() => _status = 'Code sent ✅');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Verification code sent successfully'),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
        codeAutoRetrievalTimeout: (verificationId) {
          debugPrint('Code auto-retrieval timeout: $verificationId');
          _verificationId = verificationId;
        },
        timeout: const Duration(seconds: 60),
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('FirebaseAuthException in verifyPhoneNumber: ${e.code} - ${e.message}');
      if (mounted) {
        String errorMessage = 'Authentication error';
        if (e.code == 'invalid-phone-number') {
          errorMessage = 'Invalid phone number format. Use +971XXXXXXXXX';
        } else if (e.code == 'too-many-requests') {
          errorMessage = 'Too many requests. Please try again later.';
        } else if (e.code == 'quota-exceeded') {
          errorMessage = 'SMS quota exceeded. Please try again later.';
        } else {
          errorMessage = e.message ?? e.code;
        }
        
        setState(() => _status = 'Error: $errorMessage');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Unexpected error in verifyPhoneNumber: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        setState(() => _status = 'Unexpected error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An error occurred: ${e.toString()}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _verifyCode() async {
    if (!mounted) return;
    
    if (_verificationId == null) {
      setState(() => _status = 'Please send code first');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please send verification code first')),
      );
      return;
    }
    
    final smsCode = _code.text.trim();
    if (smsCode.isEmpty) {
      setState(() => _status = 'Please enter verification code');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter verification code')),
      );
      return;
    }
    
    setState(() => _status = 'Verifying...');
    
    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );
      await FirebaseAuth.instance.signInWithCredential(cred);
      if (mounted) {
        setState(() => _status = 'Signed in ✅');
        Navigator.of(context).pushReplacementNamed('/authGate');
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('FirebaseAuthException in signInWithCredential: ${e.code} - ${e.message}');
      if (mounted) {
        String errorMessage = 'Verification failed';
        if (e.code == 'invalid-verification-code') {
          errorMessage = 'Invalid verification code. Please try again.';
        } else if (e.code == 'session-expired') {
          errorMessage = 'Verification session expired. Please request a new code.';
        } else {
          errorMessage = e.message ?? e.code;
        }
        
        setState(() => _status = 'Verification failed: $errorMessage');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Unexpected error in verifyCode: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        setState(() => _status = 'Verification failed: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification error: ${e.toString()}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const UnifiedAppBar(title: 'Auth Test'),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (kDevBypassOtp)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Development Mode',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'For iOS Simulator: Use Firebase Test phone numbers from Firebase Console.\n'
                      'For Android Emulator: Use real phone numbers or test numbers.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              )
            else
              const Text(
                'Enter your phone number to receive a verification code',
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
