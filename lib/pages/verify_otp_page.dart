import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/unified_app_bar.dart';
import 'create_profile_page.dart';
import 'listing_flow_gate_page.dart';

class VerifyOtpPage extends StatefulWidget {
  final String verificationId;
  final String phoneNumber;
  final String? returnAuctionId;
  final bool returnToListing;

  const VerifyOtpPage({
    super.key,
    required this.verificationId,
    required this.phoneNumber,
    this.returnAuctionId,
    this.returnToListing = false,
  });

  @override
  State<VerifyOtpPage> createState() => _VerifyOtpPageState();
}

class _VerifyOtpPageState extends State<VerifyOtpPage> {
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verifyCode() async {
    if (!mounted) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final smsCode = _codeController.text.trim();

    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: widget.verificationId,
        smsCode: smsCode,
      );
      await FirebaseAuth.instance.signInWithCredential(cred);

      if (!mounted) return;
      final firestore = FirestoreService();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final userExists = await firestore.userExists(user.uid);

      if (mounted) {
        if (userExists) {
          if (widget.returnAuctionId != null) {
            Navigator.of(context).popUntil((r) => r.isFirst);
            Navigator.of(context).pushNamed('/auctionDetail?auctionId=${widget.returnAuctionId}');
          } else if (widget.returnToListing) {
            Navigator.of(context).popUntil((r) => r.isFirst);
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ListingFlowGatePage()),
            );
          } else {
            Navigator.of(context).pushReplacementNamed('/authGate');
          }
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => CreateProfilePage(
                returnAuctionId: widget.returnAuctionId,
                returnToListing: widget.returnToListing,
              ),
            ),
          );
        }
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

        setState(() {
          _isLoading = false;
          _errorMessage = errorMessage;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('Unexpected error in verifyCode: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Verification error. Please try again.';
        });
      }
    }
  }

  void _onCancel() {
    if (widget.returnAuctionId != null) {
      Navigator.of(context).popUntil(
          (Route<dynamic> r) => r.settings.name?.startsWith('/auctionDetail') == true);
    } else if (widget.returnToListing) {
      Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final showCancel = widget.returnAuctionId != null || widget.returnToListing;
    return Scaffold(
      appBar: UnifiedAppBar(
        title: 'Verify Code',
        leading: showCancel
            ? IconButton(icon: const Icon(Icons.close), onPressed: _onCancel)
            : null,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Logo
                      Center(
                        child: Image.asset(
                          'assets/branding/logo_light.png',
                          width: 212,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Header
                      Text(
                        'Enter Verification Code',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'We sent a code to ${widget.phoneNumber}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      
                      // OTP input
                      TextFormField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        enabled: !_isLoading,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              letterSpacing: 8,
                            ),
                        maxLength: 6,
                        decoration: InputDecoration(
                          labelText: 'Verification Code',
                          hintText: '000000',
                          prefixIcon: const Icon(Icons.lock_outline),
                          counterText: '',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter the verification code';
                          }
                          if (value.trim().length != 6) {
                            return 'Code must be 6 digits';
                          }
                          return null;
                        },
                      ),
                      
                      // Error message
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppTheme.error.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: AppTheme.error,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: AppTheme.error,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      
                      const SizedBox(height: 32),
                      
                      // Verify button
                      ElevatedButton(
                        onPressed: _isLoading ? null : _verifyCode,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text('Verify'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
