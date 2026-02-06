import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/unified_app_bar.dart';
import 'create_profile_page.dart';
import 'listing_flow_gate_page.dart';
import 'verify_otp_page.dart';

class LoginPhonePage extends StatefulWidget {
  const LoginPhonePage({super.key, this.returnAuctionId, this.returnToListing = false});

  /// When set, show Cancel and return to this auction on cancel; pass to OTP/next steps.
  final String? returnAuctionId;
  /// When true, user came from Create Auction; show Cancel, return to Home on cancel, resume listing flow after login.
  final bool returnToListing;

  @override
  State<LoginPhonePage> createState() => _LoginPhonePageState();
}

class _LoginPhonePageState extends State<LoginPhonePage> {
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;

  // Dev mode flag for simulator builds - DEBUG-only
  static const bool kDevBypassOtp = kDebugMode;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _navigateAfterLogin(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userExists = await FirestoreService().userExists(user.uid);
    if (!mounted) return;
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

  Future<void> _sendCode() async {
    if (!mounted) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final nationalNumber = _phoneController.text.trim().replaceAll(' ', '');
    final phoneNumber = '+971$nationalNumber';

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (cred) async {
          try {
            await FirebaseAuth.instance.signInWithCredential(cred);
            if (mounted) {
              _navigateAfterLogin(context);
            }
          } catch (e) {
            debugPrint('Error signing in with credential: $e');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _errorMessage = 'Sign-in error. Please try again.';
              });
            }
          }
        },
        verificationFailed: (e) {
          debugPrint('Phone verification failed: ${e.code} - ${e.message}');
          if (mounted) {
            String errorMessage = 'Verification failed';
            if (e.code == 'invalid-phone-number') {
              errorMessage = 'Invalid phone number format. Use +971XXXXXXXXX';
            } else if (e.code == 'too-many-requests') {
              errorMessage = 'Too many requests. Please try again later.';
            } else if (e.code == 'quota-exceeded') {
              errorMessage = 'SMS quota exceeded. Please try again later.';
            } else {
              errorMessage = e.message ?? e.code;
            }
            
            setState(() {
              _isLoading = false;
              _errorMessage = errorMessage;
            });
          }
        },
        codeSent: (verificationId, _) {
          debugPrint('Verification code sent: $verificationId');
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => VerifyOtpPage(
                  verificationId: verificationId,
                  phoneNumber: phoneNumber,
                  returnAuctionId: widget.returnAuctionId,
                  returnToListing: widget.returnToListing,
                ),
              ),
            );
            setState(() {
              _isLoading = false;
            });
          }
        },
        codeAutoRetrievalTimeout: (verificationId) {
          debugPrint('Code auto-retrieval timeout: $verificationId');
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
        
        setState(() {
          _isLoading = false;
          _errorMessage = errorMessage;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('Unexpected error in verifyPhoneNumber: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'An error occurred. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final showCancel = widget.returnAuctionId != null || widget.returnToListing;
    return Scaffold(
      appBar: showCancel
          ? UnifiedAppBar(
              title: 'Sign in / Create account',
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _onCancel,
              ),
            )
          : null,
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
                        'Sign in / Create account',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'One flow for sign in and registration.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      
                      // Dev mode info
                      if (kDevBypassOtp)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppTheme.primaryBlue.withValues(alpha: 0.2),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: AppTheme.primaryBlue,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Development Mode: Use Firebase test phone numbers',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: AppTheme.primaryBlue,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (kDevBypassOtp) const SizedBox(height: 24),
                      
                      // Phone input
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        enabled: !_isLoading,
                        decoration: InputDecoration(
                          labelText: 'Phone Number',
                          hintText: '50 123 4567',
                          prefixIcon: const Icon(Icons.phone_outlined),
                          prefixText: '+971 ',
                          helperText: 'Enter your phone number. If you\'re new, we\'ll create your account automatically.',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your phone number';
                          }
                          final phone = value.trim();
                          if (phone.length < 9) {
                            return 'Please enter a valid phone number';
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
                      
                      // Send Code button
                      ElevatedButton(
                        onPressed: _isLoading ? null : _sendCode,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text('Send Code'),
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
