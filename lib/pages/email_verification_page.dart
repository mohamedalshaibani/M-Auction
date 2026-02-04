import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../widgets/unified_app_bar.dart';
import '../services/listing_eligibility_service.dart';
import 'listing_flow_gate_page.dart';

/// Required step in listing flow: add and verify email (Firebase email link).
/// When [returnAfterVerify] is true (e.g. from bidding flow), pop after verification instead of pushing ListingFlowGatePage.
class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({
    super.key,
    this.returnAfterVerify = false,
    this.returnAuctionId,
  });
  final bool returnAfterVerify;
  final String? returnAuctionId;

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _eligibility = ListingEligibilityService();
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefillEmail();
  }

  Future<void> _prefillEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email != null && user!.email!.trim().isNotEmpty) {
      _emailController.text = user.email!.trim();
      if (user.emailVerified) {
        if (mounted) setState(() => _sent = true);
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendVerification() async {
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'Not signed in');
      return;
    }
    final email = _emailController.text.trim();
    setState(() {
      _sending = true;
      _error = null;
      _sent = false;
    });
    try {
      await user.verifyBeforeUpdateEmail(email);
      await _eligibility.setEmail(user.uid, email, verified: false);
      if (mounted) {
        setState(() {
          _sending = false;
          _sent = true;
          _error = null;
        });
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        if (mounted) {
          setState(() {
            _sending = false;
            _error = 'For security, please sign out and sign in again, then try verifying your email.';
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.message ?? e.code;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _checkVerifiedAndContinue() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _error = null);
    try {
      await user.reload();
      final updated = FirebaseAuth.instance.currentUser;
      if (updated?.emailVerified == true) {
        await _eligibility.setEmailVerified(user.uid);
        if (!mounted) return;
        if (widget.returnAfterVerify) {
          if (widget.returnAuctionId != null) {
            Navigator.of(context).popUntil((r) => r.isFirst);
            Navigator.of(context).pushNamed('/auctionDetail?auctionId=${widget.returnAuctionId}');
          } else {
            Navigator.of(context).pop();
          }
        } else {
          Navigator.of(context).pop();
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ListingFlowGatePage()),
          );
        }
      } else {
        setState(() => _error = 'Email not verified yet. Open the link we sent to ${updated?.email ?? _emailController.text} and try again.');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _onCancel() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: UnifiedAppBar(
        title: 'Verify Email',
        leading: widget.returnAuctionId != null
            ? IconButton(icon: const Icon(Icons.close), onPressed: _onCancel)
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'To list items you must add and verify your email address.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _emailController,
                enabled: !_sending && !_sent,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter your email';
                  if (!v.contains('@') || !v.contains('.')) return 'Enter a valid email';
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(color: AppTheme.error, fontSize: 14),
                ),
              ],
              const SizedBox(height: 24),
              if (!_sent) ...[
                FilledButton(
                  onPressed: _sending ? null : _sendVerification,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _sending
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send verification link'),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.success),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.mail_outline, color: AppTheme.success),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'We sent a verification link to ${_emailController.text}. Open the link in your email, then tap below.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.textPrimary,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _checkVerifiedAndContinue,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('I\'ve verified my email – Continue'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
